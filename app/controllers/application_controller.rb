class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception
  # before_action :set_all_test_cases

  private

  # getting current user and admin status
  def current_user
    return unless session[:user_id]

    @current_user ||= User.find(session[:user_id])
  end

  def time_zone
    # prefer user's specified time zone if there is one
    if current_user
      return current_user.time_zone if current_user.time_zone
    end
    # Pick MESA HQ time as a default
    'Pacific Time (US & Canada)'
  end

  def format_time(time)
    I18n.l time.to_time.in_time_zone(time_zone), format: :short
  end

  def format_date(time)
    I18n.l time.to_time.in_time_zone(time_zone), format: '%Y-%m-%d'
  end

  def admin?
    return false unless current_user
    current_user.admin?
  end

  def self?
    @user && current_user && @user.id == current_user.id
  end

  def self_or_admin?
    admin? || self?
  end

  def parse_sha(includes: nil)
    Commit.parse_sha(params[:sha], branch: params[:branch], includes: includes)
  end

  def render_404(message = "Page not found")
    flash.now[:error] = message
    
    # Generate contextual fallback links based on what objects are available
    @fallback_links = []
    
    begin
      # Try to get branch from @selected_branch or fall back to params[:branch]
      branch_name = @selected_branch&.name || params[:branch]
      branch_obj = @selected_branch || (branch_name && Branch.named(branch_name))
      
      # If we have both commit and branch, link to the commit page
      if @commit && branch_obj
        @fallback_links << {
          path: commit_path(branch_obj.name, @commit.short_sha),
          text: "View commit #{@commit.short_sha} on #{branch_obj.name}",
          icon: "code-branch"
        }
      end
      
      # If we have test case and branch, link to test case page
      if @test_case && branch_obj
        @fallback_links << {
          path: test_case_path(branch_obj.name, @test_case.module, @test_case.name),
          text: "View #{@test_case.module}/#{@test_case.name} test case",
          icon: "flask"
        }
      end
      
      # If we have just a branch, link to branch commits
      if branch_obj && !(@commit && @test_case)
        @fallback_links << {
          path: commits_path(branch_obj.name),
          text: "Browse #{branch_obj.name} branch commits",
          icon: "list-ul"
        }
      end
    rescue => e
      # If any path generation fails, we'll just skip those links
      Rails.logger.warn "Error generating fallback links in render_404: #{e.message}"
    end
    
    # Always provide a safe fallback to root
    @fallback_links << {
      path: root_path,
      text: "Return to Main Page",
      icon: "home"
    }
    
    render template: "errors/not_found", status: :not_found, layout: "application"
  end

  helper_method :current_user
  helper_method :time_zone
  helper_method :format_time
  helper_method :format_date
  helper_method :admin?
  helper_method :self?
  helper_method :self_or_admin?
  helper_method :parse_sha

  # filters for accessing resources reserved for users or admins
  def authorize_user
    return unless current_user.nil?
    redirect_to login_url, alert: 'Must be logged in for that action.'
  end

  def authorize_admin
    return if admin?
    redirect_to login_url, alert: 'Must be an admin to do that action.'
  end

  def authorize_self_or_admin
    return if self_or_admin?
    redirect_to login_url, alert: 'Must be an admin or the owner of this '\
                                  'resource to do that action.'
  end

  # so that the menubar in every page can access the test case inventory
  # this should probably be generalized to use TestCase.modules rather
  # than having hard-coded modules...
  # TODO: rely on TestCase.modules
  def set_all_test_cases
    @all_test_cases ||= TestCase.modules.inject([]) do |res, mod|
      res + TestCase.where(module: mod).order(name: :asc)
    end
  end
end
