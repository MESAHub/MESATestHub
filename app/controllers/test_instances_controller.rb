class TestInstancesController < ApplicationController
  before_action :set_test_case, except: [:submit, :search, :search_count]
  before_action :set_test_instance, only: %i[show edit update destroy]
  # set_user depends on @test_instance being set, so it can only be used
  # where set_test_instance has already been called.
  before_action :set_user, only: %i[edit update destroy]
  skip_before_action :verify_authenticity_token, only: [:submit]

  # note that submit does some fancy footwork on the fly
  before_action :authorize_self_or_admin, only: %i[edit update destroy]
  before_action :authorize_user, only: %i[new create]

  # GET /test_instances
  # GET /test_instances.json
  def index
    @test_instances = 
      @test_case.test_instances.includes(:computer, :version)
                .order(mesa_version: :desc, created_at: :desc)
                .page(params[:page])
  end

  # GET /test_instances/1
  # GET /test_instances/1.json
  def show
    @passage_class = @test_instance.passed ? 'text-success' : 'text-danger'
    @passage_status = @test_instance.passage_status
    @self_or_admin = admin? || (@user && @user.id == current_user.id)
  end

  # GET /test_instances/search
  # GET /test_instances/search.json
  def search
    # @test_instances = TestInstance.all.includes(:computer, :version, :test_case).page(params[:page])
    failures = []
    @test_instances, failures = 
      TestInstance.query(params[:query_text]) if params[:query_text]
    respond_to do |format|
      format.html do
        if @test_instances
          @test_instances = @test_instances.page(params[:page])
        end
        unless failures.empty?
          flash[:warning] = 'Invalid search parameters: ' + 
                            failures.join(', ') + '.'
        end
        @show_instructions = @test_instances.nil?
      end
      format.json do
        if @test_instances
          render json: {"results" => @test_instances,
                        "failures" => failures}.to_json
        else
          render json: {"results" => [], "failures" => failures}.to_json
        end
      end
    end
  end

  def search_count
    failures = []
    @test_instances, failures = 
      TestInstance.query(params[:query_text]) if params[:query_text]
    respond_to do |format|
      format.json { render json: @test_instances.count.to_json }
    end
  end

  # GET /test_instances/new
  def new
    @test_instance = @test_case.test_instances.build
  end

  # GET /test_instances/1/edit
  def edit
    @show_path = test_case_test_instance_path(@test_case, @test_instance)
  end

  # POST /test_instances/submit
  # POST /test_instances/submit.json
  def submit
    # we are authenticated from params or session
    if submission_authenticated?
      @test_instance = submission_instance
      submission_save
    # params authentication failed. Redirect (html) or report failure (JSON)
    else
      submission_fail_authentication
    end
  end

  # POST /test_instances
  # POST /test_instances.json
  def create
    @test_instance = @test_case.test_instances.build(test_instance_params)

    # jankety solution to set version properly, similar to
    # Version#update_version
    version = Version.find_or_create_by(
      number: test_instance_params[:mesa_version])
    @test_instance.version = version    

    respond_to do |format|
      if @test_instance.save
        format.html do
          redirect_to test_case_test_instances_url(@test_case),
                      notice: 'Test instance was successfully created.'
        end
        format.json { render :show, status: :created, location: @test_instance }
      else
        format.html { render :new }
        format.json do
          render json: @test_instance.errors, status: :unprocessable_entity
        end
      end
    end
  end

  # PATCH/PUT /test_instances/1
  # PATCH/PUT /test_instances/1.json
  def update
    respond_to do |format|
      if @test_instance.update(test_instance_params)
        # jankety solution to set version properly
        @test_instance.update_version(true)

        format.html do
          redirect_to test_case_test_instances_url(@test_case),
                      notice: 'Test instance was successfully updated.'
        end
        format.json { render :show, status: :ok, location: @test_instance }
      else
        format.html { render :edit }
        format.json do
          render json: @test_instance.errors, status: :unprocessable_entity
        end
      end
    end
  end

  # DELETE /test_instances/1
  # DELETE /test_instances/1.json
  def destroy
    session[:return_to] ||= request.referer
    @test_instance.destroy
    respond_to do |format|
      format.html do
        # redirect_to test_case_test_instances_url(@test_instance.test_case),
        redirect_to session.delete(:return_to),
                    notice: 'Test instance was successfully destroyed.'
      end
      format.json { head :no_content }
    end
  end

  private

  # the following methods are helper (read: shorter) methods used as part of
  # the "submit" controller action meant to streamline that definition
  def submission_authenticated?
    # If logged on to website, we're good
    @user = current_user
    authenticated = !@user.nil?

    # If not logged on, or submitting via JSON post (likely), check params
    unless authenticated
      @user = User.find_by(email: params[:email])
      authenticated = @user && @user.authenticate(params[:password])
    end

    authenticated
  end

  def submission_instance
    instance = TestInstance.new(submission_instance_params)
    # find the appropriate test_case and computer
    # note that if the test case is not found, it is created and the
    # appropriate module is set. The module parameter is ignored for existing
    # test cases
    instance.set_test_case_name(params[:test_case], params[:mod])
    instance.set_computer_name(@user, params[:computer])
    # this allows for backwards compatibility before the version model existed
    instance.update_version
    instance
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

  def submission_set_data
    # set each datum during a submission; currently irrelevant since the
    # mesa_test gem doesn't know how to submit extra data
    data_params.each do |data_name, data_val|
      datum = @test_instance.test_data.build(name: data_name)
      datum.value = data_val
      datum.save!
    end
  end

  def submission_save
    # attempt to save submitted test instance and punt to a different method
    # depending on the outcome
    respond_to do |format|
      if @test_instance.save
        submission_successful_save(format)
      else
        submission_fail_save(format)
      end
    end
  end

  def submission_fail_save(format)
    # what to do when saving a submitted test instance fails
    format.html { render :new }
    format.json do
      render json: @test_instance.errors,
             status: :unprocessable_entity
    end
  end

  def submission_successful_save(format)
    # what to do when saving a submitted test instance is successful
    @test_case = @test_instance.test_case
    submission_set_data
    format.html do
      redirect_to test_case_test_instances_url(@test_case),
                  notice: 'Test instance was successfully created.'
    end
    format.json do
      render :show, status: :created, location:
        test_case_test_instance_path(@test_case, @test_instance)
    end
  end

  # Use callbacks to share common setup or constraints between actions.
  def set_test_instance
    @test_instance = @test_case.test_instances.includes(:test_case_version).find(params[:id])
  end

  def set_test_case
    @test_case = TestCase.find(params[:test_case_id])
  end

  def set_user
    @user = @test_instance.computer.user
  end

  # Never trust parameters from the scary internet, only allow the white list
  # through.

  # these are params used in submission that are NOT used for creating the
  # instance itself. :test_case and :computer are used for discerning foreign
  # keys, but do not go into the actual build command. The data names are
  # used for creating asscoicated test_data objects. :mod is the module of the
  # test and is only used if making a new test case out of nowhere.
  def submission_bonus_keys
    [:email, :password, :test_case, :mod, :computer,
     *@test_case.data_names.map(&:to_sym)]
  end

  def instance_keys
    %i[runtime_seconds mesa_version omp_num_threads compiler compiler_version
       platform_version passed failure_type success_type steps retries backups
       summary_text diff checksum total_runtime_seconds re_time rn_mem re_mem]
  end

  # allowed params for using the submit controller action
  def submission_params
    params.permit(*[instance_keys, submission_bonus_keys].flatten)
  end

  # once we're in submit, these are the params used to build the new instance
  def submission_instance_params
    new_hash = {}
    instance_keys.each do |key|
      new_hash[key] = params[key] if params[key]
    end
    new_hash
  end

  def data_params
    submission_params.select do |key, _value|
      @test_case.data_names.include? key.to_s
    end
  end

  # for traditional update/create process
  def test_instance_params
    params.require(:test_instance).permit(
      :runtime_seconds, :mesa_version, :omp_num_threads, :compiler,
      :compiler_version, :platform_version, :passed, :computer_id,
      :test_case_id, :success_type, :failure_type, :steps, :retries, :backups,
      :summary_text, :diff, :checksum, :total_runtime_seconds, :re_time,
      :rn_mem, :re_mem
    )
  end

  def search_params
    params.permit(:search_query).permit(
      :test_case, :passed, :user, :computer, :version, :min_version, 
      :max_version, :platform, :platform_version, :rn_RAM_min, :rn_RAM_max,
      :re_RAM_min, :re_RAM_max, :date, :date_min, :date_max, :rn_runtime_min,
      :rn_runtime_max, :re_runtime_min, :re_runtime_max, :threads,
      :threads_min, :threads_max, :compiler, :compiler_version, :query_text)
  end
end
