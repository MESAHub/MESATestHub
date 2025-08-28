class Rack::Attack
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

  # Block requests from specific IPs that are known bad actors
  # blocklist('block bad actors') do |req|
  #   # Add specific IP addresses here if needed
  #   # ['1.2.3.4', '5.6.7.8'].include?(req.ip)
  # end

  # Throttle general requests by IP (only for unauthenticated users)
  # Allow 300 requests per 5 minutes per IP
  # Authenticated users are safelisted above and bypass this limit
  throttle('req/ip', limit: 300, period: 5.minutes) do |req|
    req.ip
  end

  # Throttle login attempts by IP (applies to everyone to prevent brute force)
  # Allow 10 login attempts per 20 minutes per IP
  throttle('logins/ip', limit: 10, period: 20.minutes) do |req|
    if req.path == '/login' && req.post?
      req.ip
    end
  end

  # Throttle API submissions more strictly (only for unauthenticated requests)
  # Allow 100 API requests per 10 minutes per IP
  # Legitimate test result submissions should authenticate
  throttle('api/ip', limit: 100, period: 10.minutes) do |req|
    if req.path.match(/\.(json)$/) || req.path.start_with?('/submissions')
      req.ip
    end
  end

  # Throttle searches to prevent abuse (only for unauthenticated users)
  # Allow 30 search requests per 5 minutes per IP  
  throttle('search/ip', limit: 30, period: 5.minutes) do |req|
    if req.path.include?('search')
      req.ip
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
      Rails.logger.warn "[Rack::Attack] #{match_type} #{req.ip} #{req.request_method} #{req.fullpath}"
    end
  end
end