class VersionsController < ApplicationController

  skip_before_action :verify_authenticity_token, only: [:submit_revision]

  def index
    @versions = Version.all.includes(:test_instances, :test_cases).order(number: :desc)
    @row_classes = {}
    @computer_counts = {}
    @pass_counts = {}
    @fail_counts = {}
    @mix_counts = {}
    @case_counts = {}
    @last_tested = {}
    @versions.each do |version|
      status, pass_count, fail_count, mix_count = version.summary_status
      @row_classes[version] = case status
                              when 0 then 'table-success'
                              when 1 then 'table-danger'
                              when 2 then 'table-warning'
                              else
                                'row-info'
                              end
      @pass_counts[version] = pass_count
      @fail_counts[version] = fail_count
      @mix_counts[version] = mix_count
      @computer_counts[version] = version.test_cases.map do |test_case|
        version.computers_count(test_case)
      end.max
      @case_counts[version] = version.test_cases.uniq.length
    end
  end

  def show
    @mesa_versions = Version.order(number: :desc).pluck(:number)
    @selected = params[:number] || 'latest'
    # big daddy query, hopefully optimized
    @version_number = case @selected
                      when 'latest' then @mesa_versions.max
                      else
                        @selected.to_i
                      end
    @version = Version.includes(:test_cases, test_instances: :computer)
                      .find_by(number: @version_number)
                      
    passing, mixed, failing = @version.passing_mixed_failing_test_cases
    @test_cases = [mixed, failing, passing].flatten
    
    @header_text = "Test Cases Tested on Version #{@version_number}"
    @specs = @version.computer_specs
    @statistics = @version.statistics
    status, @pass_count, @fail_count, @mix_count = @version.summary_status
    @version_status = case status
                      when 0 then :passing
                      when 1 then :failing
                      when 2 then :mixed
                      else
                        :untested
                      end

    @status_text = case @version_status
                   when :passing then 'All tests passing on all computers.'
                   when :mixed
                     'Some tests fail on at least some computers.'
                   when :failing then 'All tests fail with all computers.'
                   else
                     'No tests have been run for this version.'
                   end

    @status_class = case @version_status
                    when :passing then 'text-success'
                    when :mixed then 'text-warning'
                    when :failing then 'text-danger'
                    else
                      'text-info'
                    end

    # for populating version select menu
    @mesa_versions.prepend('latest')

    # set up colored table rows depending on passage status
    @computer_counts = {}
    @last_versions = {}
    @row_classes = {}
    @last_tested = {}
    @test_cases.each do |t|
      @computer_counts[t] = @version.computers_count(t)
      @last_tested[t] = @version.last_tested(t)
      @row_classes[t] =
        case @version.status(t)
        when 0 then 'table-success'
        when 1 then 'table-danger'
        else
          'table-warning'
        end
    end

  end

  def show_version
    puts "redirecting to #{version_path(params[:number])}"
    redirect_to version_path(params[:number])
  end

  # FOR SUBMITTING WHOLE REVISIONS

  # POST /versions/submit_revision.json
  def submit_revision
    submission_fail_authenticate unless submission_authenticated?
    submit_version
    # iterate through each test case and submit each as an instance
    # collect failed save attempts along the way (successful submissions return
    # nil, so only hold onto non-nil results)
    failures = test_instance_pairs.map do |instance_pair|
      submit_instance(instance_params(instance_pair),
                      extra_params(instance_pair))
    end.reject { |elt| elt.nil? }
    # if some failed, send back a failure message at the end
    unless failures.empty?
      errors = failures.map { |ti| ti.errors }
      respond_to do |format|
        format.json { render json: errors.to_json, status: :unprocessable_entity }
      end
    end

    respond_to do |format|
      format.json do
        render :show, status: :created, location: version_path(@version.number)
      end
    end
  end

  def submit_version
    # first find/create version
    @version = Version.find_or_create_by(number: version_params[:number])
    # check/update svn data
    @version.author = version_params[:author] if version_params[:author]
    @version.log = version_params[:log] if version_params[:log]
    
    # bail out and report failure if we can't even get the version right
    unless @version.save
      respond_to do |format|
        format.json do
          render json: @version.errors, status: :unprocessable_entity
        end
      end
    end
  end

  def submit_instance(ti_params, extra_params)
    # set up basic test instance
    test_instance = @version.test_instances.build(ti_params)

    # set up associations
    test_instance.set_test_case_name(extra_params[:test_case],
                                     extra_params[:mod])
    test_instance.set_computer_name(@user, user_params[:computer])

    # return nil if we successfully save, otherwise the failed test_instance
    if test_instance.save
      nil
    else
      test_instance
    end
  end

  private

  def submission_authenticated?
    # If logged on to website, we're good
    @user = current_user
    authenticated = !@user.nil?

    # If not logged on, or submitting via JSON post (likely), check params
    unless authenticated
      @user = User.find_by(email: user_params[:email])
      authenticated = @user && @user.authenticate(user_params[:password])
    end
    authenticated
  end

  def submission_fail_authenticate
    # what to do when authentication during a submit fails
    respond_to do |format|
      format.html do
        redirect_to login_url,
                    alert: 'Must be signed in to submit a test instance.'
      end
      format.json do
        render json: { error: 'Invalid e-mail or password.' },
               status: :unprocessable_entity
      end
    end
  end  

  def submission_fail_authenticate
    # what to do when authentication during a submit fails
    respond_to do |format|
      format.html do
        redirect_to login_url,
                    alert: 'Must be signed in to submit a revision.'
      end
      format.json do
        render json: { error: 'Invalid e-mail or password.' },
               status: :unprocessable_entity
      end
    end
  end

  def version_params
    params.require(:version).permit(:number, :log, :author)
  end

  def test_instance_pairs
    params.require(:instances)
  end

  def user_params
    params.require(:user).permit(:email, :password, :computer)
  end

  def instance_params(instance_pair)
    instance_pair.require(:test_instance).permit(
      :runtime_seconds, :omp_num_threads, :compiler, :compiler_version,
      :platform_version, :passed, :failure_type, :success_type, :steps,
      :retries, :backups, :summary_text)
  end

  def extra_params(instance_pair)
    instance_pair.require(:extra).permit(:test_case, :mod)
  end


end
