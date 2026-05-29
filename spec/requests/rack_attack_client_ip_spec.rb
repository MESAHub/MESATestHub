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

  # Cloudflare fronts the site; its edge lives in published ranges like
  # 162.158.0.0/15 and 172.64.0.0/13. The real client only survives if both
  # the Railway hop AND the Cloudflare hop are stripped from X-Forwarded-For.
  let(:cloudflare_edge) { '162.158.1.1' }

  it 'trusts Railway 100.64.0.0/10 so remote_ip is the forwarded client' do
    expect(Rails.application.config.action_dispatch.trusted_proxies)
      .to include(an_object_satisfying { |p| p === IPAddr.new('100.64.0.14') })
  end

  it 'trusts Cloudflare edge ranges so remote_ip is the forwarded client' do
    expect(Rails.application.config.action_dispatch.trusted_proxies)
      .to include(an_object_satisfying { |p| p === IPAddr.new('162.158.1.1') })
    expect(Rails.application.config.action_dispatch.trusted_proxies)
      .to include(an_object_satisfying { |p| p === IPAddr.new('172.71.0.1') })
  end

  it 'blocks a blocklisted client forwarded through Cloudflare then Railway' do
    # The full production hop chain: real client -> Cloudflare edge -> Railway
    # proxy. X-Forwarded-For carries the client first, then the Cloudflare edge;
    # REMOTE_ADDR is the Railway proxy. Both proxy hops must be stripped for the
    # blocklist to see the real 47.79.* client again.
    get '/',
        headers: {
          'REMOTE_ADDR' => railway_proxy,
          'X-Forwarded-For' => "47.79.1.1, #{cloudflare_edge}"
        }

    expect(response).to have_http_status(:forbidden)
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
