module LogProxy
  extend ActiveSupport::Concern

  # Hard cap on a single proxied log's bytesize. A runaway log would
  # otherwise pin the Rails process while it buffers and balloon the
  # browser's parsing time. 5 MB is comfortably more than every
  # observed real build/test log in the MESA fleet; if a future
  # ProcessSubmission grows past it, the action returns 413 with a
  # direct upstream URL so the user can still get the bytes.
  LOG_BYTES_MAX = 5.megabytes

  # Time spent waiting for the upstream TCP/TLS handshake. Anything
  # past 5s is almost certainly DNS or routing trouble; the user
  # would rather see a fast error than a hung tab.
  LOG_OPEN_TIMEOUT = 5

  # Time the upstream gets to keep emitting bytes once the body
  # starts. 15s is generous for the few-KB logs we typically proxy.
  LOG_READ_TIMEOUT = 15

  # HEAD-probe cache TTL. Completed logs never change; in-flight
  # builds rarely upload-then-disappear, so 10 minutes is the
  # sweet spot between freshness and not hammering the upstream.
  LOG_STATUS_CACHE_TTL = 10.minutes

  # Custom signal types for the proxy. Each maps to a different HTTP
  # status + user-facing message at the action layer.
  class LogNotFound   < StandardError; end
  class LogTooLarge   < StandardError; end
  class LogFetchError < StandardError; end

  module_function

  # GET the upstream `uri` and return the body as a single String.
  # Raises {LogNotFound, LogTooLarge, LogFetchError} so the calling
  # action can shape the right response per failure mode.
  def fetch_log(uri)
    require "net/http"

    Net::HTTP.start(uri.host, uri.port,
                    use_ssl: uri.scheme == "https",
                    open_timeout: LOG_OPEN_TIMEOUT,
                    read_timeout: LOG_READ_TIMEOUT) do |http|
      request = Net::HTTP::Get.new(uri.request_uri)
      http.request(request) do |response|
        case response
        when Net::HTTPNotFound
          raise LogNotFound
        when Net::HTTPSuccess
          buffer = +""
          response.read_body do |chunk|
            buffer << chunk
            raise LogTooLarge if buffer.bytesize > LOG_BYTES_MAX
          end
          return buffer
        else
          raise LogFetchError, "upstream returned #{response.code}"
        end
      end
    end
  rescue LogNotFound, LogTooLarge
    raise
  rescue Net::OpenTimeout, Net::ReadTimeout => e
    raise LogFetchError, "timeout (#{e.class.name.demodulize})"
  rescue StandardError => e
    raise LogFetchError, e.message
  end

  # HEAD-probe a single upstream URL. Returns true iff the upstream
  # returns 2xx. Swallows timeouts and other network errors as "not
  # available" — the worst case is a disabled affordance the user
  # could re-enable by reloading after the upstream recovers.
  def probe_log_url(uri)
    require "net/http"

    Net::HTTP.start(uri.host, uri.port,
                    use_ssl: uri.scheme == "https",
                    open_timeout: LOG_OPEN_TIMEOUT,
                    read_timeout: LOG_OPEN_TIMEOUT) do |http|
      response = http.request(Net::HTTP::Head.new(uri.request_uri))
      response.is_a?(Net::HTTPSuccess)
    end
  rescue StandardError
    false
  end
end
