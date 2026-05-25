class ComputersController < ApplicationController
  layout "modern", only: %i[index index_all show new create edit update]

  # Hard ceiling on bulk submission deletion. The `destroy_all` path
  # instantiates each Submission and runs its `after_commit
  # :update_commit` callback (which re-aggregates the affected
  # commit + per-TCC scalars). 500 already triggers hundreds of
  # follow-up writes; beyond that the user should narrow the filter
  # and delete in chunks instead of holding open a slow request.
  BULK_DESTROY_LIMIT = 500

  before_action :set_user, only: %i[show new create index edit update destroy
                                    destroy_submissions]
  before_action :set_computer, only: %i[show edit update destroy
                                        destroy_submissions]
  before_action :authorize_self_or_admin, only: %i[new create edit update
                                                   destroy destroy_submissions]
  before_action :authorize_admin, only: %i[index_all]

  skip_before_action :authorize_user, only: [:check_computer]
  skip_before_action :verify_authenticity_token, only: [:check_computer]

  # GET /computers
  # GET /computers.json
  def index
    @owner_prefix = "#{@user.name}'s"
    @sort = sanitize_sort(params[:sort], allow_maintainer: false)
    @computers = @user.computers.ordered(@sort).page(params[:page])
  end

  def index_all
    @owner_prefix = 'All'
    @show_users = true
    @sort = sanitize_sort(params[:sort], allow_maintainer: true)
    @computers = Computer.includes(:user).ordered(@sort).page(params[:page])
    render 'index'
  end

  # GET /computers/1
  # GET /computers/1.json
  def show
    @filter = parse_submission_filters
    @submissions_scope = filtered_submissions_scope(@computer)
    @submissions = @submissions_scope
                   .order(created_at: :desc)
                   .page(params[:page])
    @counts = {}
    @submissions.each do |submission|
      @counts[submission] = submission.test_instances.length
    end

    # Check if there are any test instances before trying to get the earliest one
    first_instance = @computer.test_instances.order(:created_at).first
    @earliest = first_instance ? first_instance.created_at : @computer.created_at

    @cpu_times = {}

    @cpu_times[:day] =  @computer.test_instances.
      where(created_at: 1.day.ago..Time.now).sum(:cpu_hours)
    @cpu_times[:year] = @computer.test_instances.
      where(created_at: 1.year.ago..Time.now).sum(:cpu_hours)
    @cpu_times[:all] = @computer.test_instances.sum(:cpu_hours)
  end

  # DELETE /users/:user_id/computers/:id/submissions
  #
  # Bulk-deletes a set of submissions belonging to this computer.
  # Two ways to specify the set:
  #
  #   submission_ids[]=N           — explicit per-row selection
  #                                  (what the table-checkbox UI sends)
  #   select_all_matching=1        — apply the current filter scope
  #                                  and delete everything matching
  #                                  (so a user can take out a whole
  #                                  bad batch without having to
  #                                  click 25 checkboxes per page)
  #
  # Scopes IDs through `@computer.submissions` first so a hand-
  # crafted form posting another computer's submission ID can't
  # delete it — only rows that actually belong to this computer
  # are reachable. Same protection covers the
  # `select_all_matching` path since the filter scope is
  # `@computer.submissions` rooted.
  #
  # Always redirects back to the show page with the same filter
  # so the user can verify the result inline.
  def destroy_submissions
    scope = filtered_submissions_scope(@computer)

    if params[:select_all_matching] == "1"
      # Whole-filter deletion: trust the server-side filter, not
      # any IDs in the request.
    else
      ids = Array(params[:submission_ids]).map(&:to_i).reject(&:zero?)
      if ids.empty?
        redirect_to user_computer_path(@user, @computer, **filter_query_params),
                    alert: "No submissions selected to delete."
        return
      end
      scope = scope.where(id: ids)
    end

    count = scope.count
    if count.zero?
      redirect_to user_computer_path(@user, @computer, **filter_query_params),
                  alert: "No matching submissions found to delete."
      return
    end
    if count > BULK_DESTROY_LIMIT
      redirect_to user_computer_path(@user, @computer, **filter_query_params),
                  alert: "Cannot delete more than #{BULK_DESTROY_LIMIT} " \
                         "submissions at once — narrow the filter and try again. " \
                         "(#{count} matched the current selection.)"
      return
    end

    scope.destroy_all
    redirect_to user_computer_path(@user, @computer, **filter_query_params),
                notice: "Deleted #{view_context.pluralize(count, 'submission')} " \
                        "from #{@computer.name}."
  end

  # GET /computers/new
  def new
    @computer = @user.computers.build
  end

  # GET /computers/1/edit
  def edit
    @show_path = user_computer_path(@user, @computer)
  end

  # POST /computers
  # POST /computers.json
  def create
    @computer = Computer.new(computer_params)
    user = User.find(params[:computer][:user_id])
    unless admin? || (user && current_user && user.id == current_user.id)
      @computer.errors.add(:user_id, 'must be ' \
        'yourself unless you are an admin.')
    end

    # this if clause shouldn't be necessary, but I can't get it to work
    # otherwise
    if @computer.errors.any?
      render 'new', status: :unprocessable_content
    else
      respond_to do |format|
        if @computer.save
          format.html do
            redirect_to [@computer.user, @computer],
                        notice: 'Computer was successfully created.'
          end
          format.json { render :show, status: :created, location: @computer }
        else
          format.html { render :new, status: :unprocessable_content }
          format.json do
            render json: @computer.errors, status: :unprocessable_content
          end
        end
      end
    end
  end

  # PATCH/PUT /computers/1
  # PATCH/PUT /computers/1.json
  def update
    respond_to do |format|
      if params[:computer][:user_id]
        # only allow setting the computer's user to the logged in user unless
        # it's an admin. Skip the process if a user_id wasn't specified.
        user = User.find(params[:computer][:user_id])
        unless admin? || (user && current_user && user.id == current_user.id)
          @computer.errors.add(:user_id, 'must be yourself unless you are ' \
                                         'an admin.')
        end
      end

      if @computer.update(computer_params)
        format.html do
          redirect_to user_computer_path(computer_params[:user_id], @computer),
                      notice: 'Computer was successfully updated.'
        end
        format.json { render :show, status: :ok, location: @computer }
      else
        format.html { render :edit, status: :unprocessable_content }
        format.json do
          render json: @computer.errors, status: :unprocessable_content
        end
      end
    end
  end

  # DELETE /computers/1
  # DELETE /computers/1.json
  def destroy
    @computer.destroy
    respond_to do |format|
      format.html do
        redirect_to user_computers_url(@user),
                    notice: 'Computer was successfully destroyed.'
      end
      format.json { head :no_content }
    end
  end

  # POST /check_computer.json
  # pretty dumb for html, but it should work, I guess
  def check_computer
    user = User.find_by(email: check_computer_params[:email])
    if user && user.authenticate(check_computer_params[:password])
      if user.computers.find_by(name: check_computer_params[:computer_name])
        # authenticated and computer belongs to user. Proceed!
        respond_to do |format|
          format.html do
            session[:user_id] = user.id
            redirect_to user_computers_path(user)
          end
          format.json do
            # send back the all clear
            render json: {
              valid: true,
              message: 'Email, password, and computer name accepted'
            }
          end
        end
      else
        # authenticated, but computer matching fails
        respond_to do |format|
          format.html do
            session[:user_id] = user.id
            redirect_to user_computers_path(user),
                        alert: "#{params[:computer_name]} is not one of your " \
                               'computers.'
          end
          format.json do
            render json: {
              valid: false,
              message: 'Email and password are valid, but submitted computer '\
                'name does not match any computer on MESATestHub. Set it up '\
                'there first before submitting.'
            }
          end
        end
      end
    else
      # we are NOT authenticated
      respond_to do |format|
        format.html do
          flash.error = "Email or password is invalid"
          redirect_to login_path
        end
        format.json do
          render json: { valid: false, message: "Email or password are wrong."}
        end
      end
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_computer
    @computer = @user.computers.find(params[:id])
  end

  def set_user
    @user = User.find(params[:user_id])
  end

  # Never trust parameters from the scary internet, only allow the white list
  # through.
  def computer_params
    params.require(:computer).permit(:name, :user_id, :platform, :processor,
                                     :ram_gb)
  end

  def check_computer_params
    params.permit(:email, :password, :computer_name)
  end

  def authorize_self_or_admin
    return if admin? || @user.id == current_user.id
    redirect_to login_url, alert: 'Must be an admin or the user in ' \
      'question to do that action.'
  end

  # Whitelist sort param so a stale or hand-typed URL can't reach
  # an undefined branch in `Computer.ordered`. `maintainer` is only
  # meaningful on the admin all-users view since the per-user index
  # has exactly one maintainer.
  def sanitize_sort(raw, allow_maintainer:)
    allowed = allow_maintainer ? Computer::SORT_OPTIONS : Computer::SORT_OPTIONS - %w[maintainer]
    allowed.include?(raw.to_s) ? raw.to_s : "recent"
  end

  # Parse the three submission-filter URL params into a normalized
  # hash the view + controller both consume. Dates are interpreted
  # in the request's time zone so a user picking "2026-05-19" in
  # the picker actually filters that local calendar day (not the
  # UTC day). SHA is squashed to lowercase + at-least-4-chars so a
  # too-short paste doesn't accidentally match every commit.
  def parse_submission_filters
    raw_type = params[:type].to_s
    {
      from: parse_filter_date(params[:from], end_of_day: false),
      to:   parse_filter_date(params[:to],   end_of_day: true),
      sha:  params[:sha].to_s.strip.downcase.presence,
      type: Submission::TYPES.include?(raw_type) ? raw_type : nil,
      from_raw: params[:from].to_s,
      to_raw:   params[:to].to_s,
      sha_raw:  params[:sha].to_s,
      type_raw: raw_type
    }
  end

  def parse_filter_date(raw, end_of_day:)
    return nil if raw.blank?
    date = Date.parse(raw.to_s) rescue nil
    return nil if date.nil?
    zoned = date.in_time_zone(time_zone)
    end_of_day ? zoned.end_of_day : zoned.beginning_of_day
  end

  def filtered_submissions_scope(computer)
    filter = @filter ||= parse_submission_filters
    scope = computer.submissions
                    .includes(:commit, test_instances: :test_case)
                    .submitted_between(filter[:from], filter[:to])
                    .of_type(filter[:type])
    if filter[:sha] && filter[:sha].length >= 4
      scope = scope.for_commit_sha(filter[:sha])
    end
    scope
  end

  # Only the active filter params, scrubbed of empties, for use
  # when round-tripping through a redirect.
  def filter_query_params
    f = @filter ||= parse_submission_filters
    { from: f[:from_raw].presence, to: f[:to_raw].presence,
      sha:  f[:sha_raw].presence,  type: f[:type] }.compact
  end
end
