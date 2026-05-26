class TestInstancesController < ApplicationController
  layout "modern", only: [:search]

  # The JSON variants of search / search_count are the API path that
  # mesa_test (and other CLI clients) hit to read past test
  # instances. They authenticate per-request via `email` + `password`
  # params inside the `authenticated?` helper — there's no browser
  # session involved. The global `authorize_user` before_action
  # added in commit b8542bc (Sep 2025) didn't exempt this controller,
  # which silently broke every external client.
  #
  # Skip the global filter only for the JSON paths; the HTML search
  # page stays behind the login wall (intentional from b8542bc — the
  # goal there was to reduce anonymous browse traffic). The action
  # body still enforces auth via `authenticated?`. `search_count`
  # is JSON-only, so unconditional skip is fine there.
  skip_before_action :authorize_user, only: [:search, :search_count]
  before_action :gate_html_search_to_authenticated_users, only: [:search]

  # Cross-cuts every test run on every computer for every commit
  # using a single key-value query language. See
  # `TestInstance.query` for the backend.
  #
  # The JSON variant of this action is what the historic API
  # consumers hit; it requires authentication via the same
  # email/password pattern as `submissions#create`.
  def search
    failures = []
    respond_to do |format|
      format.html do
        @test_instances, failures =
          TestInstance.query(params[:query_text]) if params[:query_text]
        @test_instances = @test_instances.page(params[:page]) if @test_instances

        unless failures.empty?
          flash.now[:warning] = 'Invalid search parameters: ' +
                                failures.join(', ') + '.'
        end
        @show_instructions = @test_instances.nil?
      end

      format.json do
        return fail_authenticate_json unless authenticated?

        @test_instances, failures =
          TestInstance.query(params[:query_text]) if params[:query_text]
        if @test_instances
          render json: { "results" => @test_instances,
                         "failures" => failures }.to_json
        else
          render json: { "results" => [], "failures" => failures }.to_json
        end
      end
    end
  end

  # JSON-only cheap variant of #search that returns the result
  # count without enumerating the rows. Used by API clients that
  # want to know how big a result set would be before pulling it.
  def search_count
    failures = []
    respond_to do |format|
      format.json do
        return fail_authenticate_json unless authenticated?

        @test_instances, failures =
          TestInstance.query(params[:query_text]) if params[:query_text]
        render json: { count: @test_instances.count, failures: failures }.to_json
      end
    end
  end

  private

  # The HTML variant of #search should remain behind the same login
  # wall the rest of the browser views are. Restoring the global
  # before_action with a controller-level skip is the wrong shape
  # here because the conditional-`if:` form doesn't play well with
  # format detection (the lambda doesn't appear to be consulted
  # consistently on `skip_before_action` in Rails 8). Instead, skip
  # the global gate unconditionally and re-impose it on the HTML
  # format only.
  def gate_html_search_to_authenticated_users
    return if request.format.json?
    return if current_user
    redirect_to login_url, alert: 'Most pages are restricted to logged-in users. New accounts can only be created by an admin.'
  end

  # Authenticates the JSON-API path. Hits the existing session
  # first (so a logged-in browser making a fetch() against the
  # JSON endpoint just works) and falls back to email + password
  # params (so a long-lived CLI client can keep submitting
  # without a browser session).
  def authenticated?
    @user = current_user
    return true if @user

    @user = User.find_by(email: params[:email])
    @user && @user.authenticate(params[:password])
  end

  def fail_authenticate_json
    render json: { error: 'Invalid e-mail or password.' },
           status: :unprocessable_content
  end
end
