class SubmissionsController < ApplicationController

  def create
    # this set up @user, @computer, and @commit, and will fail the thing
    # if something is wrong in data
    return unless authenticate_submission

    @submission = Submission.new
    @submission.computer = computer
    @submission.commit = commit
    @submission.entire = commit_params[:entire]
    @submission.empty = commit_params[:empty]

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

    # at this point, we want to save the submission. If it goes haywire later,
    # we'll want a record of it
    @submission.save

    # we're done if it's empty
    succeed and return if @submission.empty?
    
    # rest handles test instances
    # 
    # first grab exising test_cases and test_case_commits in case we have them
    # handy. If we don't, we'll create an array of hashes to do a batch insert
    test_cases = TestCase.all
    test_case_commits = TestCaseCommit.where(commit: @submission.commit).
      includes(:test_case).to_a

    # make these suckers easier to get at when we're searching for them later
    @tcc_hash = {}
    test_case_commits.each do |tcc|
      @tcc_hash[tcc.test_case.name] = tcc
    end
    @test_case_hash = {}
    test_cases.each do |test_case|
      @test_case_hash[test_case.name] = test_case
    end

    # handle test instances. Creation of new test cases or test case commits
    # will happen in here
    if @submission.entire?
      create_instances
    else
      pair = test_instance_pairs.first
      # clunky and stupid array so later code works for entire or single-case
      # submissions (need to check failure array... so need a failure array)
      @failures = [
        create_one_instance(instance_params(pair), extra_params(pair))
      ]
      @failurs.reject(&:nil?)
    end

    # if something went wrong in creating the instances, report back a failure
    submission_fail_instances and return unless @failures.empty?

    # we've gotten this far, so submission is good and test instances were
    # saved
    @submission.save and succeed
  end

  private

  def create_instances
    # relies on having @submission be set

    # if there are bad test cases, errors are stored in @failures, which
    # will cause a failed submission in `create`
    @failures = test_instance_pairs.map do |instance_pair|
      create_one_instance(instance_params(instance_pair),
                          extra_params(instance_pair))
    end.reject { |elt| elt.nil? }
  end

  def create_one_instance(ti_params, extra_params)
    # set up basic test instance
    test_instance = TestInstance.new(ti_params)
    test_instance.commit = @submission.commit
    test_instance.submission = @submission

    # set up associations
    test_instance.set_computer(@user, @computer)

    # if test case already exists, should have been loaded into @test_case_hash
    if @test_case_hash.include? extra_params[:test_case]
      test_instance.test_case = @test_case_hash[extra_params[:test_case]]
    else
      # if not, set_test_case_name will create the test case for us
      # note, test instance takes care of setting or making its own
      # test_case_commit on the fly (handled at save and validation)
      # we just need to worry about test cases here (much rarer)
      test_instance.set_test_case_name(extra_params[:test_case],
        extra_params[:mod])
    end

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
    render :show, status: :created, location: submission_path(self)
  end

  def authenticate_submission
    submission_fail_authenticate and return nil unless submission_authenticated?
    @computer = @user.computers.find_by(name: submitter_params[:computer])
    if @computer.nil?
      submission_fail_computer(user, submitter_params[:computer])
      return nil
    end
    @commit = Commit.find_by_sha(commit_params[:sha])
    submission_fail_commit(commit_parmas[:sha]) and return nil unless @commit
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
    render json: errors.to_json, status: :unprocessable_entity
  end

  def submitter_params
    params.require(:submitter).permit(:email, :password, :computer)
  end

  def version_params
    params.require(:commit).permit(:sha, :compiled, :entire)
  end

  def test_instance_pairs
    params.require(:instances)
  end

  # these can be immediately shoved into the database. Easy! Only add things
  # when you add columns to the TestInstances table (and make sure you do do
  # that!)
  def instance_params(instance_pair)
    instance_pair.require(:test_instance).permit(
      :runtime_seconds, :omp_num_threads, :compiler,
      :compiler_version, :platform_version, :passed, :failure_type,
      :success_type, :steps, :retries, :backups, :summary_text, :diff,
      :checksum, :total_runtime_seconds, :re_time, :rn_mem, :re_mem)
  end

  # these are separate because they don't immediately constitute a test instance
  def extra_params(instance_pair)
    instance_pair.require(:extra).permit(:test_case, :mod)
  end



end
