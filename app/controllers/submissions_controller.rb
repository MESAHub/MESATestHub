class SubmissionsController < ApplicationController

  skip_before_action :verify_authenticity_token, only: [:create]

  def create
    # this sets up @user, @computer, and @commit, and will fail the thing
    # if something is wrong in data
    return unless authenticate_submission

    @submission = Submission.new
    @submission.computer = @computer
    @submission.commit = @commit
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

    # at this point, we want to save the submission to the database. If it goes
    # haywire later, we'll want a record of it
    @submission.save

    # we're done if it's empty
    succeed and return if @submission.empty?
    

    # handle test instances. +create_instances+ returns a list of instances
    # that failed upon saving to database.
    # 
    # Note, this works regardless of the number of test instances (one or many)
    # since in either case instances are submitted as a JSON listexit
    @failures = create_instances

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
      puts "this failed to save:"
      puts test_instance
      test_instance
    end
  end


  def succeed
    render :show, status: :created, location: submission_path(@submission)
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
    params.require(:submitter).permit(:email, :password, :computer)
  end

  def commit_params
    params.require(:commit).permit(:sha, :compiled, :entire, :empty)
  end

  # these can be immediately shoved into the database. Easy! Only add things
  # when you add columns to the TestInstances table (and make sure you do do
  # that!)
  def instances_params
    params.require(:instances)
    # instance.require(:instances).permit(
    #   :test_case, :mod, :runtime_seconds, :omp_num_threads, :compiler,
    #   :compiler_version, :platform_version, :passed, :failure_type,
    #   :success_type, :steps, :retries, :backups, :summary_text,
    #   :checksum, :total_runtime_seconds, :re_time, :rn_mem, :re_mem)
  end
end
