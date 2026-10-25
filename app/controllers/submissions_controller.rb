class SubmissionsController < ApplicationController
  skip_before_action :authorize_user
  skip_before_action :verify_authenticity_token, only: [:create]


  def create
    # this sets up @user, @computer, and @commit, and will fail the thing
    # if something is wrong in data
    return unless authenticate_submission

    @submission = Submission.new
    @submission.computer = @computer
    @submission.commit = @commit
    @submission.platform_version = submitter_params[:platform_version]
    @submission.entire = commit_params[:entire]
    @submission.empty = commit_params[:empty]
    @submission.compiler = commit_params[:compiler]
    @submission.compiler_version = commit_params[:compiler_version]
    @submission.sdk_version = commit_params[:sdk_version]
    @submission.math_backend = commit_params[:math_backend]

    # Dispatcher + claims fulfillment payload (Phase B of
    # docs/dispatcher-and-claims.md). Optional — backwards-
    # compatible with mesa_test versions that don't send a
    # `claim:` block. When a claim_id is supplied, the
    # after_create_commit callback on Submission flips the
    # matching claim to fulfilled. The `use_*` flags record what
    # the work was actually run with (used by Phase C's
    # satisfaction tracking).
    assign_claim_fulfillment(@submission)

    # only report compilation status once per go-round
    # that is, if we're reporting results test-by-test, compilation information
    # will come in an empty submission. In an entire submission, all the tests
    # are there, too, so we need compilation information now. 
    # 
    # Only time we don't record compilation information is for singleton
    # instance submissions (not entire nor empty)
    if @submission.entire? || @submission.empty?
      @submission.compiled = commit_params[:compiled]
    end

    # A combined submission is stored as a build row plus one row per test.
    return create_split if @submission.entire? && !@submission.empty?

    # Already have this exact result (same fingerprint from this computer on
    # this commit)? Don't store it twice -- answer as if it were new, so a
    # retrying client counts it as delivered.
    fingerprint = submission_fingerprint
    if (existing = duplicate_of(fingerprint))
      @submission = existing
      return succeed
    end
    @submission.fingerprint = fingerprint

    # we're done if it's empty
    if @submission.empty?
      (@submission.save && succeed and return)
    end
    
    # might need to deal with silly scoping, so initiate @failures to a 
    # non-empty array. It should get overwritten with an empty array later if
    # things go well, otherwise the submission should fail when it detects
    # a non-empty @failures array
    @failures = [1]

    # submission only gets saved if instances work
    Submission.transaction do
      # handle test instances. +create_instances+ returns a list of instances
      # that failed upon saving to database.
      # 
      # Note, this works regardless of the number of test instances (one or many)
      # since in either case instances are submitted as a JSON listexit
      @failures = create_instances

      unless @failures.empty?
        raise ActiveRecord::Rollback.new('Failure when saving test instances.')
      end

      # if something went wrong in creating the instances, report back a failure
      @submission.save

    end
    # @failures should be empty if all went well. Otherwise tell the user which
    # test cases failed to submit
    submission_fail_instances and return unless @failures.empty?

    # we've gotten this far, so submission is good and test instances were
    # saved
    succeed
  rescue ActiveRecord::RecordNotUnique
    # A concurrent request stored the same fingerprint first. Going again
    # finds it and answers this one as the duplicate it is.
    raise if @retried_duplicate

    @retried_duplicate = true
    retry
  end

  def show
    @submission = Submission.includes(
      :user, :computer,
      { test_instances: [{ instance_inlists: :inlist_data }, :test_case] },
      { commit: :branches }
    ).find(params[:id])
    @commit = @submission.commit
    @branch = if @commit.branches.include? Branch.main
                Branch.main
              else
                @commit.branches[0]
              end
    @computer = @submission.computer
    if params[:computer] && params[:computer] != @computer.name
      flash[:danger] = "That submission doesn't belong to computer "\
        "#{params[:computer]}."
      redirect_to :back
    end
    @test_instances = @submission.test_instances
    
    # picky about ordering; make all failing instances first, then passing
    # instances. Within those categories, order by module according to 
    # +TestInstance.modules+, and then within _that_, order alphabetically by
    # test case name
    res = []
    [false, true].each do |passage_status|
      TestCase.modules.each do |mod|
        res += @test_instances.select do |ti|
          ti.test_case.module == mod && (passage_status ? ti.passed : !ti.passed)
        end.sort { |t1, t2| t1.test_case.name <=> t2.test_case.name }
      end
    end
    @test_instances = res

  end 
  
  def request_commit
    return unless authenticate_submitter_and_computer

    branch = nil
    if request_commit_params[:branch]
      branch = Branch.named(commit_params[:branch])
    end

    max_age = request_commit_params[:max_age].to_i
    allow_skip = request_commit_params[:allow_skip]
    allow_optional = request_commit_params[:allow_optional]
    allow_fpe = request_commit_params[:allow_fpe]
    allow_converge = request_commit_params[:allow_converge]

    age = 1
    commit = nil
    while age <= max_age
      commit = Commit.test_candidate(
        computer: @computer,
        allow_optional: allow_optional, 
        allow_fpe: allow_fpe,
        allow_skip: allow_skip,
        allow_converge: allow_converge,
        max_age: age,
        branch: branch
      )
      # stop if we found a commit, or if we didn't, but we've reached
      # the max age before quitting
      break if commit || age == max_age
      age = [age * 2, max_age].min
    end

    if commit
      json_string = {
        'sha' => commit.sha,
        'skip' => commit.ci_skip?,
        'optional' => commit.ci_optional?,
        'optional_n' => commit.ci_optional_n || -1,
        'converge' => commit.ci_converge?,
        'fpe' => commit.ci_fpe?
      }.to_json

      respond_to do |format|
        format.json { render json: json_string }
      end

    else
      respond_to do |format|
        format.json { render json: { error: "No untested commits found." } }
      end
    end

  end


  private

  # --- Splitting combined submissions and ignoring duplicates -----------

  # A combined (`entire`) submission -- the build status plus every test's
  # results in one request -- is stored as what it reports: one build row
  # (`empty`, carrying the compile status) plus one row per test. Each can
  # then be deleted on its own, and every row means one thing, whether it
  # came in live one test at a time or in a single request afterwards.
  # One transaction: any unsaveable instance rolls everything back, as
  # before. Rows whose fingerprint is already stored are skipped. Each
  # row's refreshes are deferred and done once at the end, so a 107-test
  # submission costs one scalar refresh, not 108.
  def create_split
    fingerprints = fingerprint_params
    template = @submission
    created = []
    @failures = []
    build_row = nil
    Submission.transaction do
      build_row = duplicate_of(fingerprints['build'])
      unless build_row
        build_row = split_row(template, empty: true, compiled: template.compiled,
                                        fingerprint: fingerprints['build'], claim_id: template.claim_id)
        build_row.save!
        created << build_row
      end
      split_instance_params.each do |instance_params|
        key = instance_key(instance_params)
        next if duplicate_of(fingerprints[key])

        row = split_row(template, empty: false, compiled: nil, fingerprint: fingerprints[key])
        instance = TestInstance.submission_new(instance_params.permit!, row)
        if instance&.save
          created << row
        else
          @failures << (instance || unknown_test_case(key))
        end
      end
      raise ActiveRecord::Rollback unless @failures.empty?
    end
    return submission_fail_instances unless @failures.empty?

    refresh_after_split(created)
    @submission = build_row
    succeed
  end

  def split_row(template, empty:, compiled:, fingerprint:, claim_id: nil)
    Submission.new(
      computer: template.computer, commit: template.commit,
      platform_version: template.platform_version, compiler: template.compiler,
      compiler_version: template.compiler_version, sdk_version: template.sdk_version,
      math_backend: template.math_backend, started_at: template.started_at,
      use_fpe: template.use_fpe, use_full_inlists: template.use_full_inlists,
      use_converge: template.use_converge,
      entire: false, empty: empty, compiled: compiled, fingerprint: fingerprint,
      claim_id: claim_id, skip_scalar_refresh: true
    )
  end

  # The per-row refreshes create_split deferred, done once.
  def refresh_after_split(rows)
    tcc_ids = TestInstance.where(submission_id: rows.map(&:id)).distinct.pluck(:test_case_commit_id)
    TestCaseCommit.where(id: tcc_ids).find_each(&:update_and_save_scalars)
    @commit.reload
    @commit.update_scalars
    @commit.save
    @commit.refresh_ci_satisfaction!
  end

  # A build-only submission has no instances; a failed-build combined
  # submission may omit them too.
  def split_instance_params
    Array(params[:instances])
  end

  # Fingerprints ride in a top-level `fingerprints` hash -- "build" for
  # the build status, "<module>/<test>" for each test -- rather than inside
  # each instance, because older servers build instances straight from
  # their params and would reject an unknown key. Values are client
  # hashes; anything absent just means "no duplicate check".
  def fingerprint_params
    raw = params[:fingerprints]
    return {} unless raw.respond_to?(:to_unsafe_h)

    raw.to_unsafe_h.transform_values { |v| v.to_s[0, 128] }.reject { |_k, v| v.empty? }
  end

  # The fingerprint for a build-only or single-test submission.
  def submission_fingerprint
    fingerprints = fingerprint_params
    return fingerprints['build'] if @submission.empty?

    instances = split_instance_params
    instances.size == 1 ? fingerprints[instance_key(instances.first)] : nil
  end

  def instance_key(instance_params)
    "#{instance_params[:module].to_s.delete_prefix(':')}/#{instance_params[:test_case]}"
  end

  def duplicate_of(fingerprint)
    return nil if fingerprint.blank?

    Submission.find_by(computer: @computer, commit: @commit, fingerprint: fingerprint)
  end

  def unknown_test_case(key)
    TestInstance.new.tap { |ti| ti.errors.add(:test_case, "#{key} is not a known test case") }
  end

  def create_instances
    # relies on having @submission be set

    # if there are bad test cases, errors are stored in @failures, which
    # will cause a failed submission in `create`
    @failures = instances_params.map do |single_instance_params|
      create_one_instance(single_instance_params)
    end.reject { |elt| elt.nil? }
  end

  def create_one_instance(single_instance_params)
    # set up basic test instance
    test_instance = TestInstance.submission_new(single_instance_params.permit!,
                                                @submission)
    # An unknown test case comes back as nil; report it rather than crash.
    return unknown_test_case(instance_key(single_instance_params)) if test_instance.nil?

    # return nil if we successfully save, otherwise the failed test_instance
    # these can then be queried for their errors and reported back to the
    # submitting computer
    if test_instance.save
      nil
    else
      test_instance
    end
  end

  def succeed
    render :show, status: :created,
           location: computer_submission_url(
             computer: @computer.name, id: @submission.id, format: :json
           )
  end

  def authenticate_submission
    return nil unless authenticate_submitter_and_computer

    # commit should already exist in database if git webhooks are working 
    # properly. No need to auto-populate
    @commit = Commit.find_by_sha(commit_params[:sha])

    # if commit doesn't exist, do desperate call to update pull requests to see
    # if that does the trick and search again
    @commit ||= Commit.api_create(sha: commit_params[:sha])

    # bail out if there was no proper commit found (this would be bad!)
    submission_fail_commit(commit_params[:sha]) and return nil unless @commit

    # we got this far, so return true to indicate everything is fine
    true
  end

  # Sets @user and @computer, or renders a failure and returns false.
  # A per-computer API key (Authorization: Bearer) identifies the
  # computer by itself; without one, fall back to the legacy
  # email + password + computer name in the `submitter:` block.
  def authenticate_submitter_and_computer
    case api_key_computer
    when false then return render_invalid_api_key
    when Computer
      named = submitter_params[:computer]
      return render_api_key_computer_mismatch(named) if api_key_computer_mismatch?(named)
      @computer = api_key_computer
      @user = @computer.user
      return true
    end

    # first make sure we're authenticated to even do a submission
    submission_fail_authenticate and return false unless submission_authenticated?

    # make sure submission is from valid computer
    @computer = @user.computers.includes(:user).find_by(
      name: submitter_params[:computer])
    if @computer.nil?
      submission_fail_computer(@user, submitter_params[:computer])
      return false
    end
    true
  end

  def submission_authenticated?
    # If logged on to website, we're good
    @user = current_user
    authenticated = !@user.nil?

    # If not logged on, or submitting via JSON post (likely), check params
    unless authenticated
      @user = User.find_by(email: submitter_params[:email])
      authenticated = @user && @user.authenticate(submitter_params[:password])
    end
    authenticated
  end

  def submission_fail_authenticate
    # what to do when authentication during a submit fails
    render json: { error: 'Invalid e-mail or password.' },
           status: :unprocessable_content
  end

  def submission_fail_computer(user, computer)
    # what to do when authentication during a submit fails
    render json: {error: "User #{user} doesn't control computer #{computer}."},
           status: :unprocessable_content
  end

  def submission_fail_commit(sha)
    # what to do when the commit doesn't exist
    render json: { error: %q{Could not find commit: #{sha} in database."} },
           status: :unprocessable_content
  end

  def submission_fail_instances
    # only called if @failures has been set
    # should probably figure out a way to tell user that the submission was
    # still saved, though, even if some test cases
    errors = @failures.map { |ti| ti.errors }
    puts errors.to_json
    render json: errors.to_json, status: :unprocessable_content
  end

  # Optional: a request authenticated by API key may omit the
  # `submitter:` block (or send just `platform_version`).
  def submitter_params
    params.fetch(:submitter, {}).permit(:email, :password, :computer,
                                        :platform_version)
  end

  def commit_params
    params.require(:commit).permit(:sha, :compiled, :entire, :empty, :compiler,
                                   :compiler_version, :sdk_version,
                                   :math_backend)
  end

  # these can be immediately shoved into the database. Easy! Only add things
  # when you add columns to the TestInstances table (and make sure you do do
  # that!)
  def instances_params
    params.require(:instances) #.permit(:test_case, :module, :omp_num_threads,
                                      # :inlists, :mem_rn, :success_type,
                                      # :mem_re, :success_type, :checksum,
                                      # :outcome)
  end

  def request_commit_params
    params.permit(:allow_optional, :allow_fpe, :allow_converge, :allow_skip,
                  :max_age, :branch)
  end

  # Pulls the optional `claim:` block out of the request and
  # writes its fields onto the submission. JSON shape:
  #
  #   "claim": {
  #     "id": 8421,                          // integer, optional
  #     "started_at": "2026-05-27T12:34:56Z",
  #     "use_fpe": false,
  #     "use_full_inlists": false,
  #     "use_converge": false
  #   }
  #
  # No-op when no `claim:` key is present, so legacy mesa_test
  # versions continue to work. The `id`-vs-`claim_id` rename keeps
  # the JSON nested-namespace tidy (`claim.id`) while the column on
  # `submissions` stays `claim_id`.
  def assign_claim_fulfillment(submission)
    return unless params[:claim]

    attrs = params.require(:claim).permit(
      :id, :started_at,
      :use_fpe, :use_full_inlists, :use_converge
    ).to_h
    attrs[:claim_id] = attrs.delete(:id) if attrs.key?(:id) || attrs.key?('id')
    submission.assign_attributes(attrs)
  end
end
