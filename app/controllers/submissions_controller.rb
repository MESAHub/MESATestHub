class SubmissionsController < ApplicationController

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
    puts '#' * 20
    puts '# IN REQUESTION_COMMIT #'
    puts '#' * 20
    return unless submission_authenticated?

    # make sure submission is from valid computer
    @computer = @user.computers.includes(:user).find_by(
      name: submitter_params[:computer])
    if @computer.nil?
      submission_fail_computer(user, submitter_params[:computer])
      return nil
    end

    branch = nil
    if request_commit_params[:branch]
      branch = Branch.named(commit_params[:branch])
    end

    max_age = request_commit_params[:max_age]
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
    respond_to do |format|
      format.html do
        redirect_to computer_submission_url(computer: @computer.name,
                                            id: @submission.id),
                    notice: 'Submission was successfully created.'
      end
      format.json do

        render :show, status: :created,
               location: computer_submission_url(
                 computer: @computer.name, id: @submission.id
               )
      end
    end

    # render :show, status: :created, location: submission_path(@submission), format: :json
  end

  def authenticate_submission
    # first make sure we're authenticated to even do a submission
    submission_fail_authenticate and return nil unless submission_authenticated?

    # make sure submission is from valid computer
    @computer = @user.computers.includes(:user).find_by(
      name: submitter_params[:computer])
    if @computer.nil?
      submission_fail_computer(user, submitter_params[:computer])
      return nil
    end

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
           status: :unprocessable_entity
  end

  def submission_fail_computer(user, computer)
    # what to do when authentication during a submit fails
    render json: {error: "User #{user} doesn't control computer #{computer}."},
           status: :unprocessable_entity
  end

  def submission_fail_commit(sha)
    # what to do when the commit doesn't exist
    render json: { error: %q{Could not find commit: #{sha} in database."} },
           status: :unprocessable_entity
  end

  def submission_fail_instances
    # only called if @failures has been set
    # should probably figure out a way to tell user that the submission was
    # still saved, though, even if some test cases
    errors = @failures.map { |ti| ti.errors }
    puts errors.to_json
    render json: errors.to_json, status: :unprocessable_entity
  end

  def submitter_params
    params.require(:submitter).permit(:email, :password, :computer,
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
end
