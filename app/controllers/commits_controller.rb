class CommitsController < ApplicationController
  skip_before_action :authorize_user, only: :show, if: :root_page?
  before_action :set_commit, only: :show
  layout "modern", only: [:index, :show]

  # Branch lookup for the commit detail page. The :branch URL segment
  # might disagree with where the commit actually lives — old branch
  # got merged, user typed a typo, etc. If we can't find the branch
  # named in the URL but the commit does live on `main`, prefer that;
  # otherwise fall back to whatever branch first claims the commit.
  # In either fallback case we redirect so the URL agrees with the
  # branch we ended up using.
  def show
    @selected_branch = Branch.includes(:head).named(CGI.unescape(params[:branch]))
    unless @selected_branch
      @selected_branch = Branch.main if @commit.branches.include?(Branch.main)
      @selected_branch ||= @commit.branches.first
      redirect_to(commit_path(sha: @commit.short_sha, branch: @selected_branch.name), alert: "Branch <span class='text-monospace'>#{CGI.unescape(params[:branch])}</span> does not exist. Found commit in <span class='text-monospace'>#{@selected_branch}</span>.") and return
    end

    other_branches = @commit.branches.reject { |b| b == @selected_branch }
                                     .sort_by(&:updated_at)
    @branches = [@selected_branch, other_branches].flatten

    @commit_state    = @commit.commit_state
    @matrix          = @commit.test_computer_matrix
    @per_computer    = @commit.per_computer_summary
    @per_test        = @commit.per_test_summary
    @neighbors       = @selected_branch.commit_neighbors(@commit)
    @hero_window     = @selected_branch.focused_commit_window(@commit, size: 5)

    @last_clean_commit = @selected_branch.last_clean_commit_before(@commit)
    @diff_rows         = @commit.cells_changed_since(@last_clean_commit)

    @default_tab = @commit.default_detail_tab(state: @commit_state)
    requested = params[:tab].to_s.to_sym
    @active_tab = if %i[summary tests computers diff logs].include?(requested)
                    requested
                  else
                    @default_tab
                  end
  end

  def index
    @branches = Branch.includes(:head).order(:name)
    @branch_names = @branches.pluck(:name)
    @branch = if @branch_names.include? CGI.unescape(params[:branch])
                @branches[@branch_names.index(CGI.unescape(params[:branch]))]
              else
                redirect_to(commits_path(branch: 'main'), alert: "Branch <span class='text-monospace'>#{CGI.unescape(params[:branch])}</span> does not exist; showing commits on <span class='text-monospace'>main</span>.") and return
              end

    # Cursor pagination by commit_time. Two URL params drive it:
    #
    #   ?before=X   page of newest 25 commits with commit_time < X.
    #               Map initializes at the "newest" view (commits
    #               0..12 of the 25 visible on the left).
    #   ?after=Y    page of oldest 25 commits with commit_time > Y,
    #               displayed newest-first. Map initializes at the
    #               "oldest" view (commits 12..24) — i.e., the
    #               bridge between this page and the older one the
    #               user just panned from.
    #
    # Bare dates parse to end-of-day for `before` (so the picked day
    # is included) and beginning-of-day for `after` (so the picked
    # day is also included). Either form is bookmarkable.
    #
    # The headline + date chip always show "on or before <newest
    # visible>" regardless of which param produced the page, so the
    # `?after=` form is a navigation detail rather than a different
    # mental model for the user.
    @page_size = (params[:per_page] || 25).to_i.clamp(5, 200)

    if params[:after].present?
      @after_time = parse_after_param(params[:after])
      rows = @branch.ordered_commits
                    .where('commits.commit_time > ?', @after_time)
                    .reorder('commits.commit_time ASC')
                    .limit(@page_size + 1)
                    .includes(:submissions,
                              test_case_commits: { test_instances: [] })
                    .to_a
      @has_more_newer = rows.size > @page_size
      rows.pop if @has_more_newer
      @commits = rows.reverse
      @map_initial_view = :oldest
      @at_head_of_history = false
    else
      @before_time_param = parse_before_param(params[:before])
      @before_explicit = params[:before].present?
      rows = @branch.ordered_commits
                    .where('commits.commit_time < ?', @before_time_param)
                    .limit(@page_size + 1)
                    .includes(:submissions,
                              test_case_commits: { test_instances: [] })
                    .to_a
      @has_more_older_via_main_fetch = rows.size > @page_size
      rows.pop if @has_more_older_via_main_fetch
      @commits = rows
      @map_initial_view = :newest
      @at_head_of_history = !@before_explicit
    end

    # Whether the opposite-direction page exists. The main fetch
    # already told us about one direction (via the +1 trick); for
    # the other we run a cheap EXISTS against the same recursive
    # CTE. On a multi-thousand-commit branch this stays sub-ms.
    if @commits.any?
      newest_visible_time = @commits.first.commit_time
      oldest_visible_time = @commits.last.commit_time
      @has_more_older =
        if defined?(@has_more_older_via_main_fetch)
          @has_more_older_via_main_fetch
        else
          Commit.from("(#{@branch.reachable_commits_sql}) AS commits")
                .where('commits.commit_time < ?', oldest_visible_time)
                .exists?
        end
      @has_more_newer ||=
        if @at_head_of_history
          false
        else
          Commit.from("(#{@branch.reachable_commits_sql}) AS commits")
                .where('commits.commit_time > ?', newest_visible_time)
                .exists?
        end
    else
      @has_more_older = false
      @has_more_newer = false
    end

    # Effective display cursor — what the headline + date chip read.
    @before_time = @commits.first&.commit_time || @before_time_param || Time.zone.now

    @older_href =
      if @has_more_older
        commits_path(branch: @branch.name, before: (@commits.last.commit_time - 1.second).iso8601)
      end
    @newer_href =
      if @has_more_newer
        commits_path(branch: @branch.name, after: @commits.first.commit_time.iso8601)
      end

    @max_num = @branch.reachable_commit_count

    # Per-commit aggregated state — feeds the status dot, pills, flag
    # chips, and the subway map. The CommitState concern memoizes its
    # queries on each Commit instance, so calling these helpers across
    # views in the same request stays cheap.
    @commit_states = @commits.each_with_object({}) do |commit, h|
      h[commit.id] = commit.commit_state
    end

    @last_activity_at = @commits.first&.commit_time
  end

  # Proxy build logs hosted at the Flatiron logs server. Two reasons
  # to fetch server-side: (1) the Railway-hosted app can't read the
  # logs cross-origin via fetch() — that bridge gets re-built when
  # `testhub.mesastar.org` repoints at Railway — and (2) we want a
  # narrow allow-list so a logged-in user can't trick the page into
  # fetching an arbitrary file (the computer name must come from a
  # real submission for this commit).
  #
  # Returns plain text. Capped at LOG_BYTES_MAX so a runaway log
  # can't OOM the server or hammer the user's browser. Timeouts are
  # short — if the upstream is slow, we'd rather 504 than hang the
  # tab.
  LOG_BYTES_MAX = 5.megabytes
  LOG_OPEN_TIMEOUT = 5
  LOG_READ_TIMEOUT = 15

  def build_log
    sha = params[:sha]
    commit = Commit.where('sha LIKE ?', "#{sha}%").first
    return render(plain: "Commit not found", status: :not_found) unless commit

    computer_name = params[:computer].to_s
    has_submission = commit.submissions
                           .joins(:computer)
                           .where(computers: { name: computer_name })
                           .exists?
    unless has_submission
      return render(plain: "Computer #{computer_name} has no submissions for this commit",
                    status: :not_found)
    end

    log_uri = URI.parse(
      "https://mesa-logs.flatironinstitute.org/" \
      "#{commit.sha}/#{ERB::Util.url_encode(computer_name)}/build.log"
    )

    begin
      body = fetch_log(log_uri)
      response.headers["Cache-Control"] = "private, max-age=300"
      render plain: body, content_type: "text/plain; charset=utf-8"
    rescue LogNotFound
      render plain: "Build log not found on Flatiron server.",
             status: :not_found, content_type: "text/plain; charset=utf-8"
    rescue LogTooLarge
      render plain: "Build log exceeds #{LOG_BYTES_MAX / 1.megabyte} MB; download directly: #{log_uri}",
             status: :payload_too_large, content_type: "text/plain; charset=utf-8"
    rescue LogFetchError => e
      render plain: "Could not fetch log (#{e.message}). Direct URL: #{log_uri}",
             status: :bad_gateway, content_type: "text/plain; charset=utf-8"
    end
  end

  # Lightweight upstream-existence check for the Logs tab. Returns
  # `{ available: bool }` so the client can disable the tab before
  # the user spends a click discovering there's no log. Cached for
  # 10 minutes because completed build logs don't change, and even
  # in-flight builds rarely upload then disappear.
  LOG_STATUS_CACHE_TTL = 10.minutes

  def build_log_status
    sha = params[:sha]
    commit = Commit.where('sha LIKE ?', "#{sha}%").first
    return render(json: { available: false, reason: "commit_not_found" }, status: :not_found) unless commit

    computer_name = params[:computer].to_s
    has_submission = commit.submissions
                           .joins(:computer)
                           .where(computers: { name: computer_name })
                           .exists?
    unless has_submission
      return render(json: { available: false, reason: "computer_not_associated" })
    end

    log_uri = URI.parse(
      "https://mesa-logs.flatironinstitute.org/" \
      "#{commit.sha}/#{ERB::Util.url_encode(computer_name)}/build.log"
    )
    cache_key = ["build_log_exists", commit.sha, computer_name].join(":")
    available = Rails.cache.fetch(cache_key, expires_in: LOG_STATUS_CACHE_TTL) do
      probe_log_url(log_uri)
    end

    render json: { available: !!available, computer: computer_name }
  end

  # API call to allow asynchronous loading of nearby commits
  def nearby_commits
    branch = Branch.includes(:head).named(CGI.unescape(params[:branch]))
    this_commit = Commit.parse_sha(params[:sha])
    commits = branch.nearby_commits(this_commit)

    res = {}
    unless commits.nil? || commits.empty?
      res[:commits] = commits.map do |commit|
        {
          short_sha: commit.short_sha,
          message_first_line: commit.message_first_line(40),
          run_optional: commit.run_optional?,
          fpe_checks: commit.fpe_checks?,
          fine_resolution: commit.fine_resolution?,
          author: commit.author,
          commit_time: format_time(commit.commit_time),
          message_rest: commit.message_rest(40),
          status: commit.status,
          url: commit_url(branch: branch.name, sha: commit.short_sha)
        }
      end
    end

    respond_to do |format|
      format.json do
        render json: res.to_json
      end
    end
  end

  private

  # Custom signal types for the build-log proxy so the action can
  # turn each failure mode into the right status/body without
  # leaking implementation details.
  class LogNotFound   < StandardError; end
  class LogTooLarge   < StandardError; end
  class LogFetchError < StandardError; end

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
          # Stream the body and cap by bytes so a many-MB log doesn't
          # balloon memory. The whole capped body still lands in a
          # single String — fine for the typical few-KB build log.
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

  # Single HEAD probe for build_log_status. Returns true iff
  # upstream returns 2xx. Swallows timeouts and other network
  # errors as "not available" — the worst case is a disabled tab
  # the user could enable by reloading after the upstream recovers.
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

  # Parse the `before=` URL parameter for cursor pagination.
  #
  #   blank        → "now" (latest commits)
  #   "2026-03-05" → end of Mar 5 in the request's time zone so the
  #                  whole day is included
  #   ISO 8601 ts  → exact moment, as produced by the Older/Newer link
  #                  builders
  #
  # Bad input falls back to "now" rather than 422-ing — this is a
  # navigation parameter, not data.
  def parse_before_param(value)
    return Time.zone.now if value.blank?

    if value.to_s.match?(/[T:]/)
      Time.zone.parse(value.to_s) || Time.zone.now
    else
      Date.parse(value.to_s).in_time_zone.end_of_day
    end
  rescue ArgumentError, Date::Error
    Time.zone.now
  end

  # Sister parser for the `after=` URL parameter — the lower-bound
  # cursor used when navigating from a page to its newer neighbor.
  # Bare dates parse to beginning-of-day so the picked day itself is
  # included in the result set.
  def parse_after_param(value)
    return nil if value.blank?

    if value.to_s.match?(/[T:]/)
      Time.zone.parse(value.to_s)
    else
      Date.parse(value.to_s).in_time_zone.beginning_of_day
    end
  rescue ArgumentError, Date::Error
    nil
  end

  def root_page?
    params[:sha] == 'head' && params[:branch] == 'main'
  end

  def set_commit
    @commit = parse_sha(includes: :branches)

    unless @commit
      redirect_to(commits_path(branch: 'main'), alert: "Could not locate commit <span class='text-monospace'>#{params[:sha]}</span> in any branch. Showing commits in <span class='text-monospace'>main</span>.") and return
    end
  end
end
