require_relative 'boot'

require 'rails/all'
require 'ipaddr'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module MESATestHub
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0
    config.cache_store = :memory_store, { size: 64.megabytes }

    # Enable rack-attack middleware (configured in initializers/rack_attack.rb)
    config.middleware.use Rack::Attack

    # Two proxy layers sit in front of this app and neither is in Rails'
    # default trusted-proxy list, so without trusting them request.remote_ip
    # resolves to a proxy address instead of the real client — silently
    # breaking rack-attack's per-IP throttles and IP-range blocklist (both
    # key off remote_ip):
    #
    #   1. Railway's edge proxy in the RFC 6598 carrier-grade NAT range
    #      (100.64.0.0/10).
    #   2. Cloudflare, which fronts testhub.mesastar.org. Its edge appends the
    #      client to X-Forwarded-For; without trusting Cloudflare's ranges,
    #      remote_ip stops at a Cloudflare edge IP (162.158.x / 172.64.x) and
    #      every bot buckets into a handful of edge addresses.
    #
    # Cloudflare's ranges are their published list (https://www.cloudflare.com/ips/);
    # they change rarely. Custom proxies are appended to
    # ActionDispatch::RemoteIp::TRUSTED_PROXIES, not replacing it. Set here
    # rather than production.rb so the behavior is identical (and testable)
    # across environments; all these ranges are infrastructure, never a real
    # client in dev or test, so trusting them everywhere is harmless.
    CLOUDFLARE_PROXY_RANGES = %w[
      173.245.48.0/20 103.21.244.0/22 103.22.200.0/22 103.31.4.0/22
      141.101.64.0/18 108.162.192.0/18 190.93.240.0/20 188.114.96.0/20
      197.234.240.0/22 198.41.128.0/17 162.158.0.0/15 104.16.0.0/13
      104.24.0.0/14 172.64.0.0/13 131.0.72.0/22
      2400:cb00::/32 2606:4700::/32 2803:f800::/32 2405:b500::/32
      2405:8100::/32 2a06:98c0::/29 2c0f:f248::/32
    ].freeze

    config.action_dispatch.trusted_proxies =
      [IPAddr.new("100.64.0.0/10")] +
      CLOUDFLARE_PROXY_RANGES.map { |cidr| IPAddr.new(cidr) }

    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration can go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded after loading
    # the framework and any gems in your application.
  end
end
