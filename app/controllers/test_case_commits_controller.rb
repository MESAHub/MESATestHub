class TestCaseCommitsController < ApplicationController
  include TestCaseCommitsHelper
  include LogProxy

  # Log-type whitelist + per-type display vocabulary for the
  # per-test log proxy. Keys match the `:type` route segment;
  # values are the upstream file extension and a human-friendly
  # name that lands in 404/error messages.
  LOG_TYPES = {
    "out" => { file: "out.txt", label: "stdout (out.txt)" },
    "mk"  => { file: "mk.txt",  label: "build (mk.txt)" },
    "err" => { file: "err.txt", label: "stderr (err.txt)" }
  }.freeze

  layout "modern", only: :show

  before_action :set_test_case_commit, only: %i[show log log_status]
  before_action :set_log_computer, only: %i[log log_status]

  def show
    @selected_branch = Branch.named(params[:branch])
    return render_404("Branch '#{params[:branch]}' not found") unless @selected_branch

    # Other branches that contain this commit, for the breadcrumb's
    # branch picker. Mirrors the pattern used on commits#show.
    other_branches = @commit.branches.reject { |b| b == @selected_branch }
                                     .sort_by(&:updated_at)
    @branches = [@selected_branch, other_branches].flatten

    # Pre-rendered row data for the instances table — all 20 columns'
    # worth of fields. The view layer renders every column; the column
    # picker is a pure client-side toggle, so we don't need to know
    # which columns are active server-side.
    @instances = @test_case_commit.test_instances
                                  .includes(:computer, instance_inlists: :inlist_data)
                                  .order("computers.name ASC, test_instances.created_at ASC")
                                  .references(:computers)
                                  .to_a
    @instance_rows = @test_case_commit.instances_for_display

    @unique_checksums = @test_case_commit.unique_checksums

    # Optional focus highlight when the user came from a specific
    # matrix cell (e.g. via `?computer=rusty`). Renders the matching
    # row in a brand-tinted background.
    @focus_computer_name = params[:computer].to_s.presence

    # Status-word / color for the headline ("is passing in <sha>").
    @status_word, @status_class = headline_status(@test_case_commit)
    @checksum_word, @checksum_class, @checksum_n = headline_checksum(@test_case_commit)

    # In-commit test picker — every test case that has a TCC on this
    # commit, sorted worst-first (failing → mixed → checksum-only →
    # passing → untested), then by module (star → binary → astero
    # per `TestCase.modules`), then alphabetically by test name.
    # Drives the dropdown wired to the headline's test pill.
    @commit_tccs = sorted_commit_tccs(
      @commit.test_case_commits.includes(:test_case).to_a
    )

    # Subway map data — a focused window of nearby commits on this
    # branch (newest-first, anchor in the middle) paired with the
    # TCC for this test on each commit. Commits where the test
    # wasn't tested still render as a gray "untested" station so the
    # spacing stays consistent across the map.
    @subway_window = @selected_branch.focused_commit_window(@commit, size: 5)
    @subway_tccs_by_commit = TestCaseCommit
                              .where(commit_id: @subway_window.map(&:id),
                                     test_case_id: @test_case.id)
                              .index_by(&:commit_id)

    # Unique computers that reported instances for this TCC, ordered
    # worst-first by their best result on this test. The Logs tab's
    # picker row reads off this list; @focus_computer_name (if set
    # by the matrix cell handoff or `?computer=`) primes the default
    # selection.
    @log_computers = computers_for_log_picker(@instances)
    @default_log_computer = @focus_computer_name.presence ||
                            @log_computers.first&.name

    # Active tab selection — honors `?tab=summary|logs` so deep
    # links work; defaults to Summary.
    requested = params[:tab].to_s.to_sym
    @active_tab = %i[summary logs].include?(requested) ? requested : :summary
  end

  def show_test_case_commit
    redirect_to test_case_commit_path(
      sha: params[:sha], test_case: params[:test_case], module: params[:module]
    )
  end

  # Proxy a single per-test log file from the Flatiron logs server.
  # Path: /<sha>/<computer>/<test_name>/<type>.txt. Validates that
  # the named computer actually submitted instances for this TCC, so
  # a URL-guessing user can't make us fetch arbitrary files.
  def log
    type = params[:type].to_s
    type_meta = LOG_TYPES[type]
    return render(plain: "Unknown log type", status: :bad_request) unless type_meta

    log_uri = log_uri_for(type_meta[:file])

    begin
      body = LogProxy.fetch_log(log_uri)
      response.headers["Cache-Control"] = "private, max-age=300"
      render plain: body, content_type: "text/plain; charset=utf-8"
    rescue LogProxy::LogNotFound
      render plain: log_not_found_message(type_meta),
             status: :not_found, content_type: "text/plain; charset=utf-8"
    rescue LogProxy::LogTooLarge
      render plain: "#{type_meta[:label]} exceeds #{LogProxy::LOG_BYTES_MAX / 1.megabyte} MB; download directly: #{log_uri}",
             status: :payload_too_large, content_type: "text/plain; charset=utf-8"
    rescue LogProxy::LogFetchError => e
      render plain: "Could not fetch #{type_meta[:label]} (#{e.message}). Direct URL: #{log_uri}",
             status: :bad_gateway, content_type: "text/plain; charset=utf-8"
    end
  end

  # HEAD-probe whether ANY log file exists for this (commit, computer,
  # test). Returns `{ available: bool, types: {out:bool, mk:bool, err:bool} }`
  # so callers can both gate visibility AND choose a sensible default
  # type. Probes all three types in parallel and caches the combined
  # result for 10 minutes (per LogProxy::LOG_STATUS_CACHE_TTL).
  def log_status
    cache_key = ["test_log_exists", @commit.sha, @log_computer_name,
                 @test_case.module, @test_case.name].join(":")
    types = Rails.cache.fetch(cache_key, expires_in: LogProxy::LOG_STATUS_CACHE_TTL) do
      LOG_TYPES.keys.each_with_object({}) do |type, h|
        h[type] = LogProxy.probe_log_url(log_uri_for(LOG_TYPES[type][:file]))
      end
    end
    any_available = types.values.any?
    render json: { available: any_available,
                   types: types,
                   computer: @log_computer_name }
  end

  private

  def set_test_case_commit
    @commit = parse_sha(includes: { test_case_commits: :test_case })
    return render_404("Commit '#{params[:sha]}' not found") unless @commit

    @test_case = TestCase.find_by(name: params[:test_case], module: params[:module])
    return render_404("Test case '#{params[:module]}/#{params[:test_case]}' not found") unless @test_case

    # For #show we want eager loading of test_instances. For the log
    # proxy actions we only need the basic association — keep this
    # path tight (a single LIMIT-1 lookup) so probing N computers
    # doesn't N+1 instance loads.
    if action_name == "show"
      @test_case_commit = TestCaseCommit.includes(
        test_instances: { instance_inlists: :inlist_data, computer: :user }
      ).find_by(commit: @commit, test_case: @test_case)
    else
      @test_case_commit = TestCaseCommit.find_by(commit: @commit, test_case: @test_case)
    end
    return render_404("No test results found for '#{@test_case.module}/#{@test_case.name}' on commit '#{@commit.short_sha}'") unless @test_case_commit
  end

  # Validate the computer named in the URL actually has instances on
  # this TCC. Defends against URL-guessing the way commits#build_log
  # validates against submissions.
  def set_log_computer
    name = params[:computer].to_s
    has_instance = @test_case_commit.test_instances
                                    .joins(:computer)
                                    .where(computers: { name: name })
                                    .exists?
    unless has_instance
      respond_to do |format|
        format.text { render plain: "No instances on #{name} for this test on this commit", status: :not_found }
        format.json { render json: { available: false, reason: "computer_not_associated" }, status: :not_found }
        format.any  { render plain: "No instances on #{name} for this test on this commit", status: :not_found }
      end
      return
    end
    @log_computer_name = name
  end

  # Upstream URI for one log file of this (commit, computer, test).
  def log_uri_for(filename)
    URI.parse(
      "https://mesa-logs.flatironinstitute.org/" \
      "#{@commit.sha}/" \
      "#{ERB::Util.url_encode(@log_computer_name)}/" \
      "#{ERB::Util.url_encode(@test_case.name)}/" \
      "#{filename}"
    )
  end

  # User-facing message when a specific log type 404s. Names the
  # exact file the user asked for so they know whether to try a
  # sibling type. Doesn't mention "test suite" or other internals
  # — the user is already in context.
  def log_not_found_message(type_meta)
    other_labels = LOG_TYPES
                     .reject { |k, _| LOG_TYPES[k][:file] == type_meta[:file] }
                     .map { |_, v| v[:file] }
    <<~MSG
      No #{type_meta[:label]} log uploaded for #{@log_computer_name}
      on #{@test_case.module}/#{@test_case.name} at #{@commit.short_sha}.

      Try the sibling types: #{other_labels.join(', ')}.
      Or check the Computers list — this computer may not have run
      this test on this commit at all.
    MSG
  end

  # Build the computer picker list for the Logs tab. One row per
  # unique computer that submitted instances for this TCC, sorted
  # worst-first so a failing computer floats to position 0 and
  # becomes the default selection.
  def computers_for_log_picker(instances)
    by_computer = instances.group_by(&:computer).reject { |c, _| c.nil? }
    rank = ->(insts) do
      passed = insts.count(&:passed)
      failed = insts.size - passed
      if failed.positive? && passed.zero? then 0       # all failed
      elsif failed.positive?              then 1       # mixed
      elsif passed.positive?              then 3       # all passed
      else                                     4
      end
    end
    by_computer.sort_by { |c, insts| [rank.call(insts), c.name.to_s] }
               .map(&:first)
  end
end
