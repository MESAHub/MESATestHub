require 'rails_helper'

# Regression coverage for the Railway proxy-IP fix.
#
# Railway terminates TLS at an edge proxy in the RFC 6598 carrier-grade NAT
# range (100.64.0.0/10) and forwards the real client in X-Forwarded-For. Rails'
# default trusted-proxy list does not include that range, so before the fix
# every request's remote_ip resolved to a Railway proxy address (100.64.x.x).
# rack-attack keyed its throttles and IP-range blocklist off that, which meant
# the blocklist could never match a real client and per-IP throttles bucketed
# the whole internet into a handful of proxy addresses. See PR for context.
RSpec.describe 'rack-attack client IP resolution behind Railway proxy',
               type: :request do
  # Simulate the Railway hop: the TCP peer (REMOTE_ADDR) is a 100.64 proxy,
  # the real client rides in X-Forwarded-For.
  let(:railway_proxy) { '100.64.0.5' }

  before { Rack::Attack.cache.store.clear }

  it 'trusts Railway 100.64.0.0/10 so remote_ip is the forwarded client' do
    expect(Rails.application.config.action_dispatch.trusted_proxies)
      .to include(an_object_satisfying { |p| p === IPAddr.new('100.64.0.14') })
  end

  it 'blocks a blocklisted client forwarded through a Railway proxy' do
    get '/',
        headers: {
          'REMOTE_ADDR' => railway_proxy,
          'X-Forwarded-For' => '47.79.1.1'
        }

    # The IP-range blocklist (/^47\.79\./) now sees the real client again,
    # rather than the trusted proxy address, and returns the 403 responder.
    expect(response).to have_http_status(:forbidden)
  end

  it 'does not block a clean client forwarded through a Railway proxy' do
    get '/login',
        headers: {
          'REMOTE_ADDR' => railway_proxy,
          'X-Forwarded-For' => '203.0.113.7'
        }

    # A single request from a non-blocklisted client is below every throttle,
    # so the public login page renders — anything but the blocklist's 403.
    expect(response).to have_http_status(:ok)
  end
end
