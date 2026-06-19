class Rack::Attack
  # Use Rails' computed client IP (ActionDispatch::RemoteIp) rather than the
  # raw Rack::Request#ip. Behind Railway's proxy the real client only arrives
  # in X-Forwarded-For; remote_ip strips trusted proxy hops (including the
  # 100.64.0.0/10 range trusted in application.rb) so throttles and the
  # IP-range blocklist below key off the actual client instead of a Railway
  # proxy address. ActionDispatch::RemoteIp runs above Rack::Attack in the
  # middleware stack, so env['action_dispatch.remote_ip'] is always populated.
  class Request < ::Rack::Request
    def remote_ip
      @remote_ip ||= (env["action_dispatch.remote_ip"] || ip).to_s
    end
  end

  # Configure cache store (uses Rails cache by default)
  Rack::Attack.cache.store = Rails.cache

  # Allow localhost requests (for development)
  safelist('allow from localhost') do |req|
    '127.0.0.1' == req.ip || '::1' == req.ip
  end

  # Allow authenticated users unlimited access
  safelist('allow authenticated users') do |req|
    # Check if user is logged in by looking for user_id in session
    req.session[:user_id].present?
  end

  # The test-client submission API authenticates via posted
  # credentials (submitter[:email] + submitter[:password], bcrypt-
  # verified in SubmissionsController), NOT a browser session — so the
  # session safelist above can never see it. A computer running the
  # MESA suite submits one POST per test case (hundreds in a burst),
  # which blew past the generic 100-per-window IP throttles even though
  # every request carries valid credentials. Treat these paths
  # specially: exempt them from the general req/ip + api/ip throttles
  # below and give them their own generous backstop. The real access
  # control is the credential + computer-ownership check in the
  # controller, not an IP throttle.
  SUBMISSION_PATH = lambda do |req|
    req.path.start_with?('/submissions')
  end

  # Block requests from specific IPs that are known bad actors
  # blocklist('block bad actors') do |req|
  #   # Add specific IP addresses here if needed
  #   # ['1.2.3.4', '5.6.7.8'].include?(req.ip)
  # end

  # Block suspicious IP ranges that generate 404 scraper traffic
  blocklist('block suspicious ranges') do |req|
    suspicious_ranges = [
      /^47\.79\./, /^159\.138\./, /^119\.(8|12|13)\./, /^189\.1\./
    ]
    suspicious_ranges.any? { |range| req.remote_ip.match?(range) }
  end

  # Throttle general requests by IP (only for unauthenticated users)
  # Allow 100 requests per 5 minutes per IP (tightened from 300 to reduce scraper abuse)
  # Authenticated users are safelisted above and bypass this limit.
  # Credential-authenticated submissions are exempt (see SUBMISSION_PATH).
  throttle('req/ip', limit: 100, period: 5.minutes) do |req|
    req.remote_ip unless SUBMISSION_PATH.call(req)
  end

  # Throttle login attempts by IP (applies to everyone to prevent brute force)
  # Allow 10 login attempts per 20 minutes per IP
  throttle('logins/ip', limit: 10, period: 20.minutes) do |req|
    if req.path == '/login' && req.post?
      req.remote_ip
    end
  end

  # Throttle other JSON API traffic by IP. Excludes the submission
  # endpoints, which carry their own credentials and get the generous
  # backstop below — keeping them here capped legitimate test clients
  # at 100 results per 10 minutes.
  throttle('api/ip', limit: 100, period: 10.minutes) do |req|
    if req.path.match(/\.(json)$/) && !SUBMISSION_PATH.call(req)
      req.remote_ip
    end
  end

  # Generous backstop for the credential-authenticated submission API.
  # Legitimate clients submit one result per test case — hundreds per
  # run — and a whole compute cluster can sit behind a single NAT'd IP,
  # so this limit is set well above any realistic burst. It exists only
  # to bound a pathological flood; actual auth happens in the controller.
  # Raise SUBMISSION_LIMIT if a large cluster ever legitimately trips it.
  SUBMISSION_LIMIT = 1000
  throttle('submissions/ip', limit: SUBMISSION_LIMIT, period: 5.minutes) do |req|
    req.remote_ip if SUBMISSION_PATH.call(req)
  end

  # Throttle searches to prevent abuse (only for unauthenticated users)
  # Allow 30 search requests per 5 minutes per IP  
  throttle('search/ip', limit: 30, period: 5.minutes) do |req|
    if req.path.include?('search')
      req.remote_ip
    end
  end

  # Throttle IPs generating many 404s on test_cases paths
  # This catches scrapers trying invalid test case combinations
  throttle('404s/ip', limit: 5, period: 1.hour) do |req|
    if req.env['PATH_INFO'].to_s.match?(/test_cases/) && !req.session[:user_id].present?
      req.remote_ip
    end
  end

  # Block requests with suspicious user agents
  blocklist('block bad user agents') do |req|
    user_agent = req.user_agent.to_s.downcase
    
    # Block common bad bot patterns
    suspicious_patterns = [
      'masscan', 'zgrab', 'sqlmap', 'nmap', 'nikto', 'dirb',
      'gobuster', 'wpscan', 'curl/7.', 'python-requests',
      'scrapy', 'bot', 'crawler', 'spider'
    ]
    
    # Allow legitimate crawlers (be selective)
    allowed_bots = [
      'googlebot', 'bingbot', 'slurp', 'duckduckbot'
    ]
    
    # Block if matches suspicious pattern and not an allowed bot
    suspicious_patterns.any? { |pattern| user_agent.include?(pattern) } &&
      !allowed_bots.any? { |bot| user_agent.include?(bot) }
  end

  # Custom response for throttled requests
  self.throttled_responder = lambda do |req|
    retry_after = (req.env['rack.attack.match_data'] || {})[:period]
    [
      429,
      {
        'Content-Type' => 'application/json',
        'Retry-After' => retry_after.to_s
      },
      [{ error: 'Rate limit exceeded. Try again later.' }.to_json]
    ]
  end

  # Custom response for blocked requests
  self.blocklisted_responder = lambda do |req|
    [
      403,
      { 'Content-Type' => 'application/json' },
      [{ error: 'Forbidden' }.to_json]
    ]
  end

  # Log blocked and throttled requests (simplified to avoid notification issues)
  ActiveSupport::Notifications.subscribe('rack.attack') do |name, start, finish, request_id, payload|
    if payload.is_a?(Hash) && payload[:request]
      req = payload[:request]
      match_type = req.env['rack.attack.match_type'] || 'unknown'
      Rails.logger.warn "[Rack::Attack] #{match_type} #{req.remote_ip} #{req.request_method} #{req.fullpath}"
    end
  end
end