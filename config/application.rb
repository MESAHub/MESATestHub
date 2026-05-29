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

    # Railway's edge proxies live in the RFC 6598 carrier-grade NAT range
    # (100.64.0.0/10), which Rails' default trusted-proxy list does NOT cover.
    # Without trusting it, every request's remote_ip resolves to a Railway
    # proxy address (100.64.x.x) instead of the real client, silently breaking
    # rack-attack's per-IP throttles and IP-range blocklist (which key off
    # remote_ip). Custom proxies are appended to
    # ActionDispatch::RemoteIp::TRUSTED_PROXIES, not replacing it. Set here
    # rather than production.rb so the behavior is identical (and testable)
    # across environments; the range is private/CGNAT and never a real client
    # in dev or test, so trusting it everywhere is harmless.
    config.action_dispatch.trusted_proxies = [IPAddr.new("100.64.0.0/10")]

    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration can go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded after loading
    # the framework and any gems in your application.
  end
end
