# Reads a per-computer API key from `Authorization: Bearer <key>`
# (docs/api-keys.md). Included in ApplicationController so every
# client-facing endpoint — submissions, claims, dispatch, search —
# can accept a key alongside the legacy email + password.
#
# A request that sends no key falls through to the old credential
# checks unchanged. A request that sends a key is judged on the key
# alone: an unknown key is rejected, never silently retried as a
# password login.
module ApiKeyAuthentication
  extend ActiveSupport::Concern

  private

  # The plaintext key from the Authorization header, or nil.
  def bearer_api_key
    request.authorization.to_s[/\ABearer\s+(\S+)\s*\z/i, 1]
  end

  # nil when no key was sent, false when the key is unknown, else the
  # key's Computer (with its last-used time refreshed).
  def api_key_computer
    return @api_key_computer if defined?(@api_key_computer)

    key = bearer_api_key
    @api_key_computer =
      if key.nil?
        nil
      elsif (computer = Computer.find_by_api_key(key))
        computer.touch_api_key_last_used!
        computer
      else
        false
      end
  end

  def render_invalid_api_key
    render json: { error: 'Invalid API key.' }, status: :unauthorized
    false
  end

  # A keyed request may still name its computer (old payload shapes
  # always do). If it names a different one, refuse rather than guess.
  def api_key_computer_mismatch?(named)
    named.present? && named != api_key_computer.name
  end

  def render_api_key_computer_mismatch(named)
    render json: { error: "This API key belongs to #{api_key_computer.name}, " \
                          "not #{named}." },
           status: :unprocessable_content
    false
  end
end
