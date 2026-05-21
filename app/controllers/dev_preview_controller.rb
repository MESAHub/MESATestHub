class DevPreviewController < ApplicationController
  # Renders Phase 4 modern-layout views with canned data so the design
  # can be reviewed in a browser without going through auth or
  # fabricating fixture data. This controller only mounts in
  # development and test (see config/routes.rb).
  skip_before_action :authorize_user
  layout "modern"

  def index
    render html: "Phase 4 preview index — visit /dev/preview/not_found to see the 404 page rendered in the modern layout.".html_safe
  end

  def not_found
    # Mirror the shape ApplicationController#render_404 hands to the
    # template (an array of fallback links). Status stays 200 so dev
    # tooling doesn't treat the preview as a hard error.
    @fallback_links = [
      { path: root_path, text: "Return to Main Page", icon: "home" }
    ]
    render template: "errors/not_found"
  end

  # Sign in transparently as the first user in the dev DB and bounce
  # to the real commits index. Lets us preview migrated pages in the
  # browser without entering credentials each time. Restricted to
  # dev/test by the route guard, so this can't run in production.
  def commits
    user = User.first
    if user.nil?
      render plain: "No users in this database — log in normally instead.", status: :ok
      return
    end
    session[:user_id] = user.id
    redirect_to commits_path(branch: params[:branch] || "main")
  end
end
