class TestInstancesController < ApplicationController
  layout "modern", only: [:search]

  # Cross-cuts every test run on every computer for every commit
  # using a single key-value query language. The query backend
  # (`TestInstance.query` on the model) is partially rotted since
  # the SVN → git transition — see the inline warning on the
  # search view + the Phase 4 follow-up note in
  # docs/frontend-modernization.md.
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
