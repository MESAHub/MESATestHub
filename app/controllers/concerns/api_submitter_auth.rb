# Shared authentication for the /api/v1 endpoints that mesa_test
# calls (claims, dispatch). Mirrors SubmissionsController exactly: a
# `submitter:` hash carrying `email` / `password` / `computer`, with
# the password verified by bcrypt against the User and the computer
# scoped to the authenticated user's computers. A logged-in browser
# session also counts, which keeps the endpoints poke-able by hand.
#
# Including controllers call `authenticate_submitter_computer` and
# get `@user` / `@computer` set on success. On failure it renders a
# 422 JSON error (the legacy submissions endpoint's auth-failure
# shape) and returns false, so callers can `return unless ...`.
module ApiSubmitterAuth
  extend ActiveSupport::Concern

  private

  def authenticate_submitter_computer
    return api_fail(:auth, 'Invalid e-mail or password.') unless submitter_authenticated?

    @computer = @user.computers.find_by(name: submitter_params[:computer])
    return true if @computer

    api_fail(:auth, "User #{@user.email} doesn't control computer " \
                    "#{submitter_params[:computer]}.")
  end

  def submitter_authenticated?
    @user = current_user
    return true if @user

    @user = User.find_by(email: submitter_params[:email])
    @user && @user.authenticate(submitter_params[:password])
  end

  def submitter_params
    params.require(:submitter).permit(:email, :password, :computer)
  end

  # Render an error and return false so callers can early-exit
  # with `return unless ...`. Status codes:
  #   :auth        → 422 (unprocessable_content) — matches the
  #                  legacy submissions endpoint's auth-failure shape
  #   :not_found   → 404 — for missing commit / TCC
  #   :bad_request → 422 — malformed request body
  def api_fail(kind, message)
    status = kind == :not_found ? :not_found : :unprocessable_content
    render json: { error: message }, status: status
    false
  end

  # Coerces a JSON boolean (true/false/0/1/"true"/etc.) to a Ruby
  # boolean, treating an absent key as false.
  def api_bool(value)
    ActiveModel::Type::Boolean.new.cast(value) || false
  end
end
