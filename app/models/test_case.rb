class TestCase < ApplicationRecord
  has_many :test_instances, dependent: :destroy
  has_many :test_case_versions, dependent: :destroy
  has_many :test_case_commits, dependent: :destroy
  has_many :computers, through: :test_instances
  has_many :versions, through: :test_instances
  has_many :commits, through: :test_instances
  has_many :users, through: :computers

  validates_presence_of :name

  # this happens to be in reverse alphabetical order, which we exploit heavily
  # in sorting
  def self.modules
    %w[star binary astero]
  end

  def self.ordered_cases(includes: nil)
    if includes.nil?
      self.where.not(module: nil).order(module: :desc, name: :asc)
    else
      self.includes(includes).all
    end
    # res = []
    # self.modules.each do |mod|
    #   res += all_cases.select { |tc| tc.module == mod }.sort do |tc1, tc2|
    #     tc1.name <=> tc2.name
    #   end
    # end
    # res
  end

  def self.current_cases(includes: nil)
    Commit.head.test_cases
  end


  validates_inclusion_of :module, in: TestCase.modules, allow_blank: true

  # def self.find_by_version(version = :all)
  #   return TestCase.all.order(:name) if version.to_s.to_sym == :all
  #   search_version = version == :latest ? versions.max : version
  #   # TestInstance is indexed on mesa version, so we get those in constant
  #   # time, then back out unique Test Cases. This is usually used to get
  #   # data for index, so eagerly load instances to get at status without
  #   # hitting database for a ton more queries
  #   TestCase.includes(:test_instances).find(
  #     TestInstance.where(
  #       mesa_version: search_version
  #     ).pluck(:test_case_id).uniq
  #   ).sort { |a, b| (a.name <=> b.name) }
  # end

  # def self.version_statistics(test_cases, version)
  #   stats = { passing: 0, mixed: 0, failing: 0 }
  #   test_cases.each do |test_case|
  #     case test_case.version_status(version)
  #     when 0 then stats[:passing] += 1
  #     when 1 then stats[:failing] += 1
  #     when 2 then stats[:mixed] += 1
  #     end
  #   end
  #   stats
  # end

  # def self.version_computer_specs(test_cases, version)
  #   specs = {}
  #   test_cases.each do |test_case|
  #     test_case.version_instances(version).each do |instance|
  #       spec = instance.computer_specification
  #       specs[spec] = [] unless specs.include?(spec)
  #       specs[spec] << instance.computer.name
  #     end
  #   end
  #   specs.each_value(&:uniq!)
  #   specs
  # end

  # for tight space when we need the name
  def short_name
    return name if name.length <= 20

    "#{name[0, 17]}..."
  end

  def <=>(other)
    res = TestCase.modules.index(self.module) <=> 
          TestCase.modules.index(other.module)
    return res unless res.zero?

    self.name <=> other.name
  end


  def find_test_case_commits(search_params, start_date, end_date)
    # start with search just on dates; can chain other things before we hit
    # the database
    valid_commit_ids = Branch.named(search_params[:branch]).commits.pluck(:id)
    query = {commit_id: valid_commit_ids}
    unless search_params[:status].nil? or search_params[:status].empty?
      query[:status] = search_params[:status]
    end

    sort_query = ''
    # by default, with most recent commits and instances first
    if search_params[:sort_query].nil? || search_params[:sort_query].empty?
      sort_query = 'commits.commit_time DESC'
    else
      # enforce a valid sort order to prevent SQL injection
      sort_order = search_params[:sort_order] || 'ASC'
      sort_order.upcase!
      unless %w{ASC DESC}.include? sort_order
        sort_order = 'ASC'
      end

      # dictionary between what was passed in (if anything), and what the
      # database understands. This is dumb and clunky.
      # 
      # For most cases, do the desired sorting, and then fall back to
      # descending timestamps (newest first).
      sort_query = case search_params[:sort_query].to_s.downcase
      when "commit" 
        "commits.commit_time #{sort_order}, test_case_commits.created_at DESC"
      when "status" 
        "test_case_commits.status #{sort_order}, test_case_commits.created_at DESC"
      when "date" 
        # these two don't have a real purpose. We could just use the test case
        # commit creation date, but that's not a useful date, and it's not
        # what the column heading says, so this is just redundant for now
        "commits.commit_time #{sort_order}, test_case_commits.created_at DESC"

        # ideally we'd be able to sort on steps/retries, etc., but it's very
        # hard (perhaps impossible?) to create database query that sorts on
        # the first association of a test case commit that is passing, but
        # not a skip case. I'm giving up at this point.
      else
        'commits.commit_time DESC, test_case_commits.created_at DESC'
      end
    end

    test_case_commits.includes(:commit,
      test_instances: {instance_inlists: :inlist_data}).
      where(query).
      order(sort_query).
      page(search_params[:page] || 1)
  end

  def find_instances(search_params, start_date, end_date)
    # build this up and then execute only once or twice
    valid_commit_ids = Branch.named(search_params[:branch]).commits.where(
      commit_time: start_date..end_date).pluck(:id)
    query = { commit_id: valid_commit_ids.reverse }

    return nil if test_instances.joins(:commit).where(query).count == 0

    # which computer/computers to look for results from
    computers = []
    if search_params[:computers]
      computers = Computer.select(:id).where(
        name: search_params[:computers]).pluck(:id)
    else
      # if no computer is selected, only show computer with most computers
      computer_ids = test_instances.joins(:commit).select(:computer_id).where(query).pluck(
        :computer_id)
      frequencies = Hash.new(0)
      computer_ids.each do |id|
        frequencies[id] += 1
      end
      computers = [computer_ids.max_by { |id| frequencies[id] }]
    end

    query[:computer_id] = computers
    unless search_params[:status].nil? || search_params[:status].empty?
      case search_params[:status].to_i
      when 0 then query[:passed] = true
      when 1 then query[:passed] = false
      end
    end

    sort_query = ''
    # by default, with most recent commits and instances first
    if search_params[:sort_query].nil? || search_params[:sort_query].empty?
      sort_query = 'commits.created_at DESC, commits.commit_time DESC, test_instances.created_at DESC'
    else
      # enforce a valid sort order to prevent SQL injection
      sort_order = search_params[:sort_order] || 'ASC'
      sort_order.upcase!
      unless %w{ASC DESC}.include? sort_order
        sort_order = 'ASC'
        puts "forced order to ASC"
      end

      # dictionary between what was passed in (if anything), and what the
      # database understands. This is dumb and clunky.
      # 
      # For most cases, do the desired sorting, and then fall back to
      # descending timestamps (newest first). Notable exceptions are commit and
      # creation timestamp ordering, which respect user input for ordering.
      sort_query = case search_params[:sort_query].to_s.downcase
      when "commit" 
        "commits.created_at #{sort_order} commits.commit_time #{sort_order}, "\
        "test_instances.created_at #{sort_order}"
      when "status" 
        "test_instances.passed #{sort_order}, test_instances.created_at DESC"
      when "date" 
        "test_instances.created_at #{sort_order}"
      when "runtime" 
        "test_instances.runtime_minutes #{sort_order}, "\
        "test_instances.created_at DESC"
      when "ram" 
        "test_instances.mem_rn #{sort_order}, test_instances.created_at DESC"
      when "spec" 
        "test_instances.computer_specification #{sort_order}, "\
        "test_instances.created_at DESC"
      # when "log_rel_run_e_err"
      #   "test_instances.log_rel_run_E_err #{sort_order}, "\
      #   "test_instances.created_at DESC"
      else
        # not one of the special cases, but we need to MAKE SURE THAT THE ENTRY
        # IS A VALID COLUMN, otherwise we are vulnerable to SQL injection
        # attack, where a clever choice of sort_query could drop whole tables
        if TestInstance.column_names.include?(search_params[:sort_query])
          "test_instances.#{search_params[:sort_query]} #{sort_order}, "\
          "test_instances.created_at DESC"
        # if not a default column, maybe it's a custom column
        elsif test_instances.inlist_data.select(:name).distinct.
          include?(search_params[:sort_query])
          "#{search_params[:sort_query].to_s} #{sort_order}, test_instances.created_at DESC"
        else
          # exhausted all possibilites, just default to created_at and hope
          # for the best
          'commits.created_at DESC, commits.commit_time DESC, test_instances.created_at DESC'
        end
      end
    end
    res = test_instances
      .includes(:commit, :test_case_commit, :inlist_data,
                { instance_inlists: :inlist_data, computer: :user })
      .where(query)
      .order(Arel.sql(sort_query))
      .page(search_params[:page] || 1)
    puts '#############################################'
    res.each do |ti|
      puts ti.created_at
    end
    puts query
    puts sort_query
    puts '#############################################'
    res
  end

  def sorted_computers(branch, start_date, end_date)
    commits = branch.commits.where(commit_time: start_date..end_date)
    all_ids = test_instances.where(commit: commits).pluck(:computer_id)
    id_counts = {}
    all_ids.uniq.each do |id|
      id_counts[id] = all_ids.count(id)
    end
    all_ids.sort! { |id1, id2| -(id_counts[id1] <=> id_counts[id2]) }
    Computer.includes(:user).find(all_ids)
  end

  # list of version numbers with test instances that have failed since a
  # particular date (handled by TestInstance... unclear where this should live)
  def self.failing_versions_since(date)
    TestInstance.failing_versions_since(date)
  end

  # list of version numbers with test instances that have passed since (with
  # none failing) a particular date (handled by TestInstance... unclear where
  # this should live)
  def self.passing_versions_since(date)
    TestInstance.passing_versions_since(date)
  end

  # list of test cases with instances that failed for a particular version
  # since a particular date (handled by TestInstance... unclear where this
  # should live)
  def self.failing_cases_since(date, version)
    TestInstance.failing_cases_since(date, version)
  end

  def last_tested
    return test_instances.maximum(:created_at) unless test_instances.loaded?
    test_instances.map(&:created_at).max
  end

  alias last_tested_date last_tested

  def last_test_status
    return 3 if test_instances.empty?
    test_instances.where(created_at: last_tested_date).first.passed ? 0 : 1
  end

  # def mesa_versions
  #   test_instances.pluck(:mesa_version).uniq.sort.reverse
  # end

  # instances that were run for a particular version
  def version_instances(version, limit = nil)
    return test_instances if version == :all
    # hit the database directly if needed
    unless test_instances.loaded?
      if limit
        return test_instances.includes(:computer)
                             .where(version: version)
                             .order(created_at: :desc)
                             .limit(limit)
      else                             
        return test_instances.includes(:computer)
                             .where(version: version)
                             .order(created_at: :desc)
      end
    end
    # instances already loaded? avoid hitting the database
    res = test_instances.select { |t| t.version_id == version.id }
                        .sort { |a, b| -(a.created_at <=> b.created_at) }
    if limit
      res.first(limit)
    else
      res
    end
  end

  # computers that have tested this case for a particular version
  def version_computers(version, limit = nil)
    version_instances(version, limit).map(&:computer).uniq
  end

  def version_status(version)
    return last_version_status if version == :all
    these_instances = version_instances(version)
    return 3 if these_instances.empty?
    passing_count = 0
    failing_count = 0
    if test_instances.loaded?
      passing_count = these_instances.select(&:passed).length
      failing_count = these_instances.reject(&:passed).length
    else
      passing_count = these_instances.where(passed: true).count
      failing_count = these_instances.where(passed: false).count
    end
    # success by default if we have at least one instance and no failures
    return 0 unless failing_count > 0
    # at least one failing, if also one passing, send back 2 (mixed). Otherwise
    # send back 1 (failing)
    passing_count > 0 ? 2 : 1
  end

  # def version_computers_count(version)
  #   unless test_instances.loaded?
  #     return version_instances(version).pluck(:computer_id).uniq.length
  #   end
  #   version_instances(version).map(&:computer_id).uniq.length
  # end

  def last_version
    return test_instances.maximum(:mesa_version) unless test_instances.loaded?
    test_instances.map(&:mesa_version).max
  end

  def last_version_status
    version_status(last_version)
  end

  ###############################################
  # Modern test_cases#show — branch-scoped helpers.
  #
  # These are intentionally narrow: they exist to feed the redesigned
  # page's headline (status sentence + counts), passage strip (~60
  # commit overview), and History tab (paginated TCC list). The legacy
  # `#find_test_case_commits` / `#find_instances` pair stays around
  # for the legacy show until that file is replaced; nothing here
  # shares state with it.
  ###############################################

  # Worst-first headline status word + Tailwind text-color class for
  # the headline sentence ("`black_hole` is **passing** on main").
  # The classification follows the most-recent TCC on the branch
  # rather than rolling up everything in the date window — the user
  # cares "what's the current state?", not "what's the average."
  HEADLINE_STATUSES = {
    1  => ["failing",  "text-danger-soft-text"],
    3  => ["mixed",    "text-warning-soft-text"],
    2  => ["checksum-divergent", "text-warning-soft-text"],
    0  => ["passing",  "text-success-soft-text"],
    -1 => ["untested", "text-fg-muted"]
  }.freeze

  # Pull together everything the modern show page's headline + Tier 2
  # summary need in one round trip. Returns:
  #
  #   {
  #     counts:        { passing:, failing:, mixed:, checksum:, untested:, total: },
  #     last_run:      TestCaseCommit | nil,   # most-recent TESTED TCC (status != -1)
  #     last_passing:  TestCaseCommit | nil,   # most-recent fully-passing TCC
  #     pending_on_head: TestCaseCommit | nil, # untested TCC newer than last_run
  #     headline_word: "passing" | "failing" | ... | "never run",
  #     headline_class: Tailwind text-color class
  #   }
  #
  # An "untested" TCC is one that exists in the DB but has no
  # submitted instances yet — `status = -1`. It doesn't count as a
  # "run" for headline purposes: the user wants the state of the
  # most recent commit *that has results*. When a newer commit
  # exists but is still pending, `pending_on_head` surfaces that
  # separately so the subline can say "Pending on aa27a08."
  #
  # Heavy queries are scoped through the branch's reachable commits
  # via `branch.ordered_commits.pluck(:id)` so divergent branches
  # don't pollute each other's counts.
  def status_summary_for(branch)
    commit_ids = branch.ordered_commits.pluck(:id)
    scope = test_case_commits.where(commit_id: commit_ids)

    raw_counts = scope.group(:status).count
    counts = {
      passing:  raw_counts[0].to_i,
      failing:  raw_counts[1].to_i,
      checksum: raw_counts[2].to_i,
      mixed:    raw_counts[3].to_i,
      untested: raw_counts[-1].to_i
    }
    counts[:total] = counts.values.sum

    last_run = scope.joins(:commit)
                    .where.not(status: -1)
                    .reorder("commits.commit_time DESC")
                    .first

    last_passing = scope.joins(:commit)
                        .where(status: 0)
                        .reorder("commits.commit_time DESC")
                        .first

    # If newer commits exist that haven't been tested yet, surface
    # the most recent one so the user knows the chart is waiting on
    # results. Skip when last_run is nil — there's no "newer than"
    # comparison to make.
    pending_on_head = if last_run
                        scope.joins(:commit)
                             .where(status: -1)
                             .where("commits.commit_time > ?", last_run.commit.commit_time)
                             .reorder("commits.commit_time DESC")
                             .first
                      end

    if last_run
      word, klass = HEADLINE_STATUSES.fetch(last_run.status, HEADLINE_STATUSES[-1])
    else
      word, klass = ["never run", "text-fg-muted"]
    end

    {
      counts: counts,
      last_run: last_run,
      last_passing: last_passing,
      pending_on_head: pending_on_head,
      headline_word: word,
      headline_class: klass
    }
  end

  # Allowed window sizes for the shared time-window toolbar. Anything
  # else gets coerced to the default. The toolbar's selector reads
  # off this list too so values stay in sync.
  WINDOW_SIZES = [25, 50, 100, 250].freeze
  DEFAULT_WINDOW_SIZE = 50

  # Single window of commits centered on `anchor_commit` for both the
  # History tab and (in the next commit) the Trend chart. Replaces the
  # earlier separate passage-strip + Kaminari-paginated history helpers
  # — investigation flows want one consistent navigation primitive, not
  # two unrelated lists.
  #
  # Returns:
  #
  #   {
  #     size:             actual window size used (coerced from input),
  #     anchor_commit:    Commit at the center of the window,
  #     at_head:          true when anchor_commit is the branch HEAD,
  #     entries:          [{ commit:, tcc:, status: }, ...], newest first,
  #     older_anchor_sha: short_sha to pass back as ?anchor= to pan older
  #                       by half a window (nil when no older commits left),
  #     newer_anchor_sha: short_sha to pass back to pan newer (nil at HEAD),
  #     window_counts:    { status_int => count } over the window only
  #   }
  #
  # Eager-loads test_instances + computers on every TCC so the
  # per-row mini-matrix renders without N+1.
  def commit_window(branch, anchor_commit:, size: DEFAULT_WINDOW_SIZE)
    size = size.to_i
    size = DEFAULT_WINDOW_SIZE unless WINDOW_SIZES.include?(size)

    return empty_commit_window(size) if anchor_commit.nil?

    commits = branch.focused_commit_window(anchor_commit, size: size)
    return empty_commit_window(size, anchor_commit) if commits.empty?

    # Eager-load everything every per-tab payload needs:
    #   - History matrix:   :computer (per-cell)
    #   - History popover:  :computer + instance_inlists/inlist_data (metrics)
    #   - Trend payload:    instance_inlists/inlist_data (custom-name
    #                       discovery + scalar metric extraction)
    # One pre-load is cheap; the N+1 alternative inside
    # _trend_metric_specs hit ~1500 queries on a 100-commit window.
    tccs_by_commit = test_case_commits
                       .includes(test_instances: [:computer, { instance_inlists: :inlist_data }])
                       .where(commit_id: commits.map(&:id))
                       .index_by(&:commit_id)

    entries = commits.map do |commit|
      tcc = tccs_by_commit[commit.id]
      { commit: commit, tcc: tcc, status: tcc&.status || -1 }
    end

    # Pan targets — the commit that should become the new anchor when
    # the user clicks "Older" / "Newer". `half` matches what the
    # window's edge would land on after a half-window pan, so the user
    # sees an overlap of half the previous window on each step
    # (continuity beats teleporting).
    half = [size / 2, 1].max
    older_target = branch.ordered_commits
                         .where("commits.commit_time < ?", anchor_commit.commit_time)
                         .limit(half)
                         .last
    newer_target = branch.ordered_commits
                         .where("commits.commit_time > ?", anchor_commit.commit_time)
                         .reorder("commits.commit_time ASC")
                         .limit(half)
                         .last

    {
      size: size,
      anchor_commit: anchor_commit,
      at_head: anchor_commit.id == branch.head_id,
      entries: entries,
      older_anchor_sha: older_target&.short_sha,
      newer_anchor_sha: newer_target&.short_sha,
      window_counts: entries.each_with_object(Hash.new(0)) { |e, h| h[e[:status]] += 1 }
    }
  end

  # Three perceptually distinct hues for the Trend chart's top-N
  # config series. Deliberately *not* the status palette (success /
  # warning / danger / info) so a "passing config's runtime" line
  # doesn't read as a status-encoded color. Indexed: configs[0]
  # gets [0], etc.
  TREND_SERIES_COLORS = ["#5b8def", "#ad55c0", "#2b9b87"].freeze

  # Top-N config tuples to show as separate series on the Trend
  # chart. The user explicitly chose 3 — few enough to keep the
  # chart readable, enough to cover the common heavy-testing
  # computers without forcing aggregation.
  TREND_TOP_CONFIGS = 3

  DEFAULT_TREND_METRIC = "runtime_minutes".freeze

  # Build the JSON payload for the Trend chart. Consumed by the
  # uPlot-backed `trend-chart` Stimulus controller via a
  # `<script type="application/json">` block in the Trend tab.
  #
  # Inputs:
  #   entries  — the same { commit:, tcc:, status: } array from
  #              #commit_window. We don't re-resolve the window
  #              here so all tabs stay in lockstep with the toolbar.
  #   top_n    — defaults to TREND_TOP_CONFIGS (3).
  #
  # Output (JSON-ready hash):
  #
  #   {
  #     default_metric: "runtime_minutes",
  #     metrics: [
  #       { id:, label:, source: "instance"|"inlist_first"|"inlist_data" }
  #     ],
  #     configs: [
  #       { key:, label:, computer:, threads:, run_optional:, count:, color: }
  #     ],
  #     commits: [
  #       { id:, sha:, t:, time_ago:, message:, status:, href: }
  #     ],   # oldest first — chart X axis goes left-to-right with time
  #     series: {
  #       "<metric_id>" => { "<config_key>" => [val | null, ...] }
  #     }
  #   }
  #
  # A `null` in a series array means "this (config, commit) pair
  # has no submitted instance" — uPlot draws a gap. Skipped
  # instances (success_type='skip') are treated as nulls too; their
  # runtime/RAM aren't meaningful comparisons.
  #
  # Returns a degenerate-but-renderable payload (empty configs,
  # empty series, but metrics/commits populated) when the window
  # has no instances. The controller renders an "not enough data"
  # empty state for that case.
  def trend_payload(branch, entries, top_n: TREND_TOP_CONFIGS)
    chrono = entries.reverse  # oldest first for the X axis
    tccs   = entries.map { |e| e[:tcc] }.compact

    # Count (computer_id, threads, run_optional) tuples across all
    # non-skipped instances in the window. Memoize a sample
    # TestInstance per tuple so we can build labels without a
    # separate Computer lookup.
    config_counts = Hash.new(0)
    config_sample = {}
    tccs.each do |tcc|
      tcc.test_instances.each do |ti|
        next if ti.success_type == "skip"
        next if ti.computer_id.nil?
        key = [ti.computer_id, ti.omp_num_threads, ti.run_optional]
        config_counts[key] += 1
        config_sample[key] ||= ti
      end
    end

    top_keys = config_counts.sort_by { |_, c| -c }.first(top_n).map(&:first)
    configs = top_keys.each_with_index.map do |key, idx|
      sample = config_sample[key]
      cname  = sample.computer&.name || "computer ##{key[0]}"
      threads = key[1] || "?"
      mode    = key[2] ? "full" : "partial"
      {
        key:          _trend_config_key(key),
        label:        "#{cname} · #{threads}t · #{mode}",
        computer:     cname,
        threads:      key[1],
        run_optional: key[2],
        count:        config_counts[key],
        color:        TREND_SERIES_COLORS[idx % TREND_SERIES_COLORS.size]
      }
    end

    commits_payload = chrono.map do |entry|
      c = entry[:commit]
      {
        id:       c.id,
        sha:      c.short_sha,
        t:        c.commit_time.to_i,
        time_ago: nil, # filled by view (helper-only context)
        message:  c.message_first_line(80),
        status:   entry[:status]
      }
    end

    metrics = _trend_metric_specs(tccs)

    # Bucket every non-skip instance once: { config_key =>
    # { commit_id => latest_instance } }. Later loops over metrics
    # read from this index without re-scanning TCCs.
    bucket = top_keys.each_with_object({}) { |k, h| h[_trend_config_key(k)] = {} }
    chrono.each do |entry|
      tcc = entry[:tcc]
      next unless tcc
      tcc.test_instances.each do |ti|
        next if ti.success_type == "skip"
        next if ti.computer_id.nil?
        key = [ti.computer_id, ti.omp_num_threads, ti.run_optional]
        next unless top_keys.include?(key)
        ck = _trend_config_key(key)
        # If multiple instances for the same (config, commit) — rare
        # but happens with re-runs — keep the most recent. The chart
        # is showing "what value did this config most recently
        # produce for this commit?"
        existing = bucket[ck][entry[:commit].id]
        bucket[ck][entry[:commit].id] = ti if existing.nil? || (ti.created_at && ti.created_at >= (existing.created_at || Time.at(0)))
      end
    end

    series = {}
    metrics.each do |m|
      series[m[:id]] = {}
      top_keys.each do |key|
        ck = _trend_config_key(key)
        series[m[:id]][ck] = chrono.map do |entry|
          ti = bucket[ck][entry[:commit].id]
          ti ? _trend_extract_value(ti, m) : nil
        end
      end
    end

    {
      default_metric: DEFAULT_TREND_METRIC,
      metrics:        metrics,
      configs:        configs,
      commits:        commits_payload,
      series:         series
    }
  end

  # ease transition from versions being hard coded to using new Version model
  def update_version_created
    return if version_id
    return unless version_added
    new_version = Version.find_or_create_by(number: version_added)
    update(version_id: new_version.id)
    new_version.number
  end

  private

  def empty_commit_window(size, anchor_commit = nil)
    {
      size: size,
      anchor_commit: anchor_commit,
      at_head: false,
      entries: [],
      older_anchor_sha: nil,
      newer_anchor_sha: nil,
      window_counts: {}
    }
  end

  # Stable string key for a (computer_id, threads, run_optional)
  # tuple. Used as the series key in the trend payload's `series`
  # hash so the Stimulus controller can address each series by a
  # string rather than coordinating array indices.
  def _trend_config_key(key)
    "c#{key[0]}-t#{key[1] || 'x'}-#{key[2] ? 'full' : 'partial'}"
  end

  # Available metrics for the Trend chart. Combines hard-coded
  # instance scalars with whatever inlist-data names are present
  # across the window's TCCs (so a test case's custom data shows
  # up automatically; nothing else to register).
  #
  # `source` tells the value extractor where to pull from:
  #   - "instance":     direct attribute on TestInstance
  #   - "inlist_first": first instance_inlist that has the named field
  #   - "inlist_data":  first inlist's inlist_data row with the given name
  def _trend_metric_specs(tccs)
    base = [
      { id: "runtime_minutes",     label: "Runtime [min]",         source: "instance" },
      { id: "mem_rn",              label: "RAM rn [GB]",           source: "instance" },
      { id: "cpu_hours",           label: "CPU hours",             source: "instance" },
      { id: "steps",               label: "Steps",                 source: "instance" },
      { id: "retries",             label: "Retries",               source: "instance" },
      { id: "redos",               label: "Redos",                 source: "instance" },
      { id: "solver_iterations",   label: "Solver iterations",     source: "instance" },
      { id: "solver_calls_made",   label: "Solver calls made",     source: "instance" },
      { id: "solver_calls_failed", label: "Solver calls failed",   source: "instance" },
      { id: "log_rel_run_E_err",   label: "log rel E err",         source: "inlist_first" }
    ]

    custom_names = Set.new
    tccs.each do |tcc|
      tcc.test_instances.each do |ti|
        ti.instance_inlists.each do |ii|
          ii.inlist_data.each { |d| custom_names << d.name if d.name.present? }
        end
      end
    end

    base + custom_names.to_a.sort.map do |name|
      { id: "inlist_data:#{name}", label: "#{name} (inlist)", source: "inlist_data" }
    end
  end

  # Pull a single metric value off an instance, honoring the
  # metric spec's `source`. Returns nil if the value isn't present
  # — the Stimulus controller turns nil into a gap on the chart.
  def _trend_extract_value(instance, metric)
    case metric[:source]
    when "instance"
      val = instance.public_send(metric[:id])
      # rn_mem_GB conversion lives on the model; mem_rn is in KB
      if metric[:id] == "mem_rn" && val
        instance.respond_to?(:rn_mem_GB) ? instance.rn_mem_GB : val / 1_048_576.0
      else
        val
      end
    when "inlist_first"
      # First inlist that has the field set (typically only one).
      target = instance.instance_inlists.find { |ii| ii.public_send(metric[:id]) }
      target&.public_send(metric[:id])
    when "inlist_data"
      datum_name = metric[:id].split(":", 2).last
      instance.instance_inlists.each do |ii|
        d = ii.inlist_data.find { |x| x.name == datum_name }
        return d.val if d
      end
      nil
    end
  end
end
