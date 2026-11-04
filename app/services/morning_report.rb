# Builds the data structure for the daily MESA Test Hub digest email.
# Both MorningMailer and MorningReportController consume one of these.
#
# A report covers the 24 hours ending at `as_of`. For a dated report
# that's the digest's send time, 8:00 AM US Eastern, so consecutive
# digests tile time with no gap. (Until Nov 2026 the window was midnight
# to midnight UTC on the send date; the 8 AM send only saw its first
# 12-13 hours, and the US working day after each send was never
# reported.)
#
# A commit is in the report when anything about it arrived in the
# window: a submission (a build report or a test result) or a claim. A
# build that failed everywhere has no test instances, so keying on
# instances alone missed exactly the commits that most need a look.
#
# Each commit appears once. Sections follow the home page: main first,
# then commits that sit on several non-main branches (stacked or
# rebased work) grouped by that branch set, then one section per
# branch. A commit on main never repeats in another branch's section,
# so a branch that merged main doesn't drag main's commits along.
#
# Statuses come from CommitState through CommitStateCache, the same
# source as the home page's pills and rings, so the email says what the
# site says.
#
# Build the report through `MorningReport.for(date:)`. A finished day's
# report is cached so the email and the web preview agree; a day whose
# send time hasn't come yet is built live with the window ending now.
class MorningReport
  WINDOW = 24.hours
  ZONE = 'America/New_York'.freeze
  SEND_HOUR = 8
  CACHE_VERSION = 2

  # Cohort math knobs. The cohort is the previous `COHORT_LIMIT` passing
  # instances with the same cohort key (see #cohort_key) from before the
  # window — anything older or in a different cohort is irrelevant.
  COHORT_LIMIT = 50
  COHORT_LOOKBACK = 180.days
  COHORT_MIN_SIZE = 8        # need at least this many samples for stats
  ANOMALY_Z_THRESHOLD = 3.0  # require >= 3 sigma above cohort mean
  ANOMALY_RATIO_FLOOR = 1.25 # AND >= 25% above cohort mean (protects
                             # against tiny-stddev cohorts where 3σ is
                             # still a meaningless absolute jump)
  # AND an absolute jump big enough to matter. Memory is nearly
  # deterministic, so its stddev is tiny and z alone flags any change.
  ANOMALY_MIN_DELTA = {
    runtime: 1.0,        # minutes
    rn_mem: 256 * 1024,  # kB (256 MB)
    re_mem: 256 * 1024
  }.freeze

  attr_reader :date, :window_start, :window_end, :sections, :anomalies,
              :computers_reporting, :release_blocker_count

  # The date whose digest goes out (or went out) this morning, Eastern.
  def self.current_date
    Time.current.in_time_zone(ZONE).to_date
  end

  # When the digest for `date` is sent: 8:00 AM US Eastern.
  def self.send_time(date)
    ActiveSupport::TimeZone[ZONE].local(date.year, date.month, date.day, SEND_HOUR)
  end

  def self.for(date: current_date, force: false)
    as_of = send_time(date)
    # Not sent yet: a live preview of what would go out, never cached.
    return new(as_of: Time.current).build if as_of > Time.current

    cache_key = "morning_report:v#{CACHE_VERSION}:#{date.iso8601}"
    Rails.cache.delete(cache_key) if force
    Rails.cache.fetch(cache_key, expires_in: 24.hours) do
      new(as_of: as_of).build
    end
  end

  def initialize(as_of: Time.current)
    @window_end = as_of
    @window_start = as_of - WINDOW
    @date = as_of.in_time_zone(ZONE).to_date
    @sections = []
    @anomalies = []
    @computers_reporting = 0
  end

  def build
    load_commits
    load_anomalies
    @release_blocker_count = fetch_release_blocker_count
    self
  end

  # Every commit in the window, once each.
  def commits_tested
    @commits_tested ||= []
  end

  def any_commits?
    commits_tested.any?
  end

  def summaries
    sections.flat_map(&:commit_summaries)
  end

  # Commits with failing tests or a failed build, worst first, each once.
  def attention_summaries
    summaries.select(&:needs_attention?).sort_by(&:severity_rank)
  end

  def any_failing?
    summaries.any?(&:needs_attention?)
  end

  def any_anomalies?
    anomalies.any?
  end

  # ===== Inner data classes =====

  # One group of commits. `kind` is :main, :family (several branches
  # that share commits, e.g. a stack), :branch, or :unattached (no
  # branch at all: PR test-merge commits, or a push whose membership
  # hasn't synced).
  Section = Struct.new(:kind, :branch_names, :commit_summaries,
                       keyword_init: true) do
    def title
      case kind
      when :family then "#{branch_names.size} related branches"
      when :unattached then 'Unattached commits'
      else branch_names.first
      end
    end

    def commit_count
      commit_summaries.size
    end

    def attention_count
      commit_summaries.count(&:needs_attention?)
    end

    def current_summaries
      commit_summaries.reject(&:rewritten)
    end

    def rewritten_summaries
      commit_summaries.select(&:rewritten)
    end
  end

  # Per-commit roll-up. `state` is CommitState#commit_state. The problem
  # test lists come from the commit's TCCs, worst-first, with FPE-only
  # failures split out of failing/mixed. `link_branch_name` is the
  # branch its URLs go through (nil when it's on no branch, since such
  # a commit has no page). `rewritten` marks a commit a force-push
  # dropped; `replacement` is the commit that took its place, if known.
  CommitSummary = Struct.new(
    :commit, :state, :branch_names, :link_branch_name,
    :rewritten, :replacement,
    :failing_tccs, :mixed_tccs, :fpe_tccs, :checksum_tccs,
    :failed_build_computers,
    keyword_init: true
  ) do
    def tests_status
      state[:tests][:status]
    end

    def build_status
      state[:build][:status]
    end

    def tests
      state[:tests]
    end

    def build_failed?
      %i[some_fail all_fail].include?(build_status)
    end

    # A commit a force-push dropped is superseded work: listed, but not
    # something to fix.
    def needs_attention?
      return false if rewritten

      %i[fail mixed fpe].include?(tests_status) || build_failed?
    end

    # For ordering the attention list: failed builds and uniform
    # failures first, then mixed, then FPE.
    def severity_rank
      return 0 if build_status == :all_fail
      { fail: 1, mixed: 3, fpe: 4 }.fetch(tests_status, build_failed? ? 2 : 5)
    end

    def computer_count
      (state[:build][:built_computer_ids] | state[:build][:failed_build_computer_ids]).size
    end

    def problem_tccs
      failing_tccs + mixed_tccs + fpe_tccs + checksum_tccs
    end

    # Badge key for one of `problem_tccs`.
    def label_for(tcc)
      return :fpe if fpe_tccs.include?(tcc)
      return :checksums if checksum_tccs.include?(tcc)
      mixed_tccs.include?(tcc) ? :mixed : :failing
    end
  end

  # One flagged metric on one test instance. `metric` is :runtime,
  # :rn_mem, or :re_mem. Runtime is stored in minutes, memory in kB.
  Anomaly = Struct.new(
    :test_instance, :metric, :value, :cohort_mean, :cohort_stddev,
    :cohort_size, :z_score, :ratio, :occurrences,
    keyword_init: true
  ) do
    METRIC_LABEL = {
      runtime: 'Runtime',
      rn_mem: 'rn RAM',
      re_mem: 're RAM'
    }.freeze

    def memory?
      metric != :runtime
    end

    def label
      METRIC_LABEL[metric]
    end
  end

  private

  def window
    window_start..window_end
  end

  def load_commits
    submitted = Submission.where(created_at: window)
    activity = submitted.group(:commit_id).maximum(:created_at)
    Claim.where(created_at: window).group(:commit_id).maximum(:created_at)
         .each { |id, at| activity[id] = [activity[id], at].compact.max }
    activity.delete(nil)
    return if activity.empty?

    @computers_reporting = submitted.distinct.count(:computer_id)

    commits = Commit.where(id: activity.keys)
                    .includes(test_case_commits: :test_case,
                              branch_memberships: { branch: :head })
                    .order(corrected_time: :desc, id: :desc).to_a
    @commits_tested = commits
    states = CommitStateCache.fetch(commits)
    computer_names = Computer.where(
      id: states.values.flat_map { |s| s[:build][:failed_build_computer_ids] }
    ).pluck(:id, :name).to_h

    # A commit a force-push dropped has no memberships left, but its
    # page still renders on the branch it was dropped from (with a "no
    # longer on this branch" banner), so it files under that branch.
    rewrites = CommitRewrite.where(old_commit_id: commits.map(&:id))
                            .includes(:new_commit, branch: :head)
                            .group_by(&:old_commit_id)

    placed = commits.map do |commit|
      branches = commit.branch_memberships.map(&:branch).compact
      rewrite = nil
      if branches.empty? && (rewrite = rewrites[commit.id]&.max_by(&:rewritten_at))
        branches = rewrites[commit.id].map(&:branch).uniq
      end
      [commit, branches, rewrite]
    end

    @sections = group_into_sections(placed, activity).map do |kind, names, rows|
      Section.new(
        kind: kind, branch_names: names,
        commit_summaries: rows.map do |commit, branches, rewrite|
          build_summary(commit, states[commit.id], branches: branches,
                        rewrite: rewrite, computer_names: computer_names)
        end
      )
    end
  end

  # [[kind, branch_names, rows]] in display order. Main's commits come
  # first. The rest are split into families: branches joined by any
  # commit they share, so a stack of branches (each one built on the
  # last) reads as one section with each commit once, rather than one
  # section per branch repeating the commits underneath it. A family
  # of one branch is plain :branch. Commits on no branch go last.
  def group_into_sections(placed, activity)
    main_rows, rest = placed.partition { |_, bs, _| bs.any? { |b| b.name == 'main' } }
    unattached, branched = rest.partition { |_, bs, _| bs.empty? }

    # Union-find over branch names.
    parent = {}
    find = lambda do |x|
      parent[x] ||= x
      parent[x] == x ? x : (parent[x] = find.call(parent[x]))
    end
    branched.each do |_, bs, _|
      names = bs.map(&:name)
      names.each { |n| parent[find.call(n)] = find.call(names.first) }
    end
    families = branched.group_by { |_, bs, _| find.call(bs.first.name) }

    latest = ->(rows) { -rows.map { |c, _, _| activity[c.id].to_f }.max }
    sections = families.values.map do |rows|
      names = rows.flat_map { |_, bs, _| bs.map(&:name) }.uniq.sort
      [names.size > 1 ? :family : :branch, names, rows]
    end
    sections.sort_by! { |kind, names, rows| [kind == :family ? 0 : 1, latest.call(rows), names] }

    sections.unshift([:main, ['main'], main_rows]) if main_rows.any?
    sections << [:unattached, [], unattached] if unattached.any?
    sections
  end

  # The branch a commit's links go through: main when it's on main,
  # else the one pushed most recently, as Commit#preferred_branch picks.
  def link_branch_for(branches)
    return nil if branches.empty?
    return 'main' if branches.any? { |b| b.name == 'main' }

    branches.min_by { |b| [-(b.head&.commit_time&.to_i || 0), b.name] }.name
  end

  def build_summary(commit, state, branches: [], rewrite: nil, computer_names: {})
    tccs = commit.test_case_commits.to_a
    # Failing/mixed TCCs whose every failure was a trapped
    # floating-point exception get their own bucket — still stored as
    # failing/mixed, but a different kind of problem.
    fpe_ids = fpe_only_tcc_ids(tccs.select { |t| [1, 3].include?(t.status) })
    fpe_tccs, other_tccs = tccs.partition { |t| fpe_ids.include?(t.id) }
    by_name = ->(list) { list.sort_by { |t| t.test_case.name.to_s } }
    CommitSummary.new(
      commit: commit,
      state: state,
      branch_names: branches.map(&:name).sort,
      link_branch_name: link_branch_for(branches),
      rewritten: rewrite.present?,
      replacement: rewrite&.new_commit,
      failing_tccs: by_name.call(other_tccs.select { |t| t.status == 1 }),
      mixed_tccs: by_name.call(other_tccs.select { |t| t.status == 3 }),
      fpe_tccs: by_name.call(fpe_tccs),
      checksum_tccs: by_name.call(other_tccs.select { |t| t.status == 2 }),
      failed_build_computers: state[:build][:failed_build_computer_ids]
        .map { |id| computer_names[id] }.compact.sort
    )
  end

  # Ids of the given TCCs whose failing instances are all FPE
  # failures — reported (failure_type 'fpe') or likely (failed with
  # FPE checks on while the same computer passed that test with them
  # off; the SQL twin of TestInstance.fpe_failure_kind). One grouped
  # query per commit.
  def fpe_only_tcc_ids(tccs)
    return Set.new if tccs.empty?
    likely = <<~SQL.squish
      COALESCE(test_instances.fpe_checks, false) AND EXISTS (
        SELECT 1 FROM test_instances ok
        WHERE ok.test_case_commit_id = test_instances.test_case_commit_id
          AND ok.computer_id = test_instances.computer_id
          AND ok.passed AND NOT COALESCE(ok.fpe_checks, false))
    SQL
    TestInstance.where(test_case_commit_id: tccs.map(&:id), passed: false)
                .group(:test_case_commit_id)
                .having(Arel.sql("BOOL_AND(COALESCE(test_instances.failure_type = 'fpe', false) OR (#{likely}))"))
                .pluck(:test_case_commit_id)
                .to_set
  end

  # ===== Anomalies =====

  METRIC_TO_COLUMN = {
    runtime: :runtime_minutes,
    rn_mem: :mem_rn,
    re_mem: :mem_re
  }.freeze

  # Passing results that arrived in the window, each compared with the
  # last COHORT_LIMIT passing runs of the same cohort from before the
  # window. (runtime_seconds / re_time / total_runtime_seconds, which
  # this used to read, are never written, so it never flagged anything.)
  def load_anomalies
    return if commits_tested.empty?

    candidates = TestInstance
      .where(created_at: window, passed: true, commit_id: commits_tested.map(&:id))
      .includes(:test_case, :computer, :commit)
      .to_a
    return if candidates.empty?

    stats = cohort_stats(candidates)
    candidates.each do |ti|
      s = stats[cohort_key(ti)]
      flag_anomalies(ti, s) if s
    end
    @anomalies = dedupe_anomalies(@anomalies)
  end

  # One entry per (test, computer, metric): the same slowdown on three
  # commits is one finding. Keeps the worst and counts the rest.
  def dedupe_anomalies(list)
    list.group_by { |a| [a.test_instance.test_case_id, a.test_instance.computer_id, a.metric] }
        .map { |_, group| group.max_by(&:ratio).tap { |a| a.occurrences = group.size } }
        .sort_by { |a| -a.ratio }
  end

  # Runs are comparable when they ran the same test on the same machine
  # the same way: full or default inlists, FPE checks, convergence
  # factor, and thread count (runtime scales with threads).
  def cohort_key(ti)
    [ti.test_case_id, ti.computer_id, !!ti.run_optional, !!ti.fpe_checks,
     (ti.resolution_factor || 1.0).to_f, ti.omp_num_threads]
  end

  # { cohort_key => { metric => {mean:, stddev:, count:} } }, from one
  # windowed query over every cohort the candidates need.
  def cohort_stats(candidates)
    sql = <<~SQL.squish
      SELECT test_case_id, computer_id, run_optional, fpe_checks,
             resolution_factor, omp_num_threads,
             runtime_minutes, mem_rn, mem_re
      FROM (
        SELECT test_instances.*, ROW_NUMBER() OVER (
          PARTITION BY test_case_id, computer_id,
                       COALESCE(run_optional, false), COALESCE(fpe_checks, false),
                       COALESCE(resolution_factor, 1.0), omp_num_threads
          ORDER BY created_at DESC) AS cohort_rank
        FROM test_instances
        WHERE passed
          AND created_at < :start AND created_at >= :lookback
          AND test_case_id IN (:test_case_ids)
          AND computer_id IN (:computer_ids)
      ) ranked
      WHERE cohort_rank <= :limit
    SQL
    rows = TestInstance.connection.select_rows(
      TestInstance.sanitize_sql([sql, {
        start: window_start, lookback: window_start - COHORT_LOOKBACK,
        test_case_ids: candidates.map(&:test_case_id).uniq,
        computer_ids: candidates.map(&:computer_id).uniq,
        limit: COHORT_LIMIT
      }])
    )
    bool = ActiveModel::Type::Boolean.new
    rows.group_by do |tc, comp, opt, fpe, factor, threads, *_|
      [tc.to_i, comp.to_i, !!bool.cast(opt), !!bool.cast(fpe),
       (factor || 1.0).to_f, threads&.to_i]
    end.transform_values do |group|
      METRIC_TO_COLUMN.keys.each_with_index.to_h do |metric, i|
        [metric, column_stats(group.map { |r| r[6 + i] })]
      end
    end
  end

  def column_stats(values)
    values = values.compact.map(&:to_f)
    return nil if values.size < COHORT_MIN_SIZE

    mean = values.sum / values.size
    variance = values.sum { |v| (v - mean)**2 } / values.size
    { mean: mean, stddev: Math.sqrt(variance), count: values.size }
  end

  def flag_anomalies(test_instance, stats)
    METRIC_TO_COLUMN.each do |metric, column|
      stat = stats[metric]
      next unless stat

      value = test_instance.public_send(column)
      next if value.nil? || value.zero?
      next if stat[:mean].zero?

      ratio = value.to_f / stat[:mean]
      next if ratio < ANOMALY_RATIO_FLOOR
      next if value - stat[:mean] < ANOMALY_MIN_DELTA[metric]

      z = stat[:stddev].zero? ? Float::INFINITY :
                                (value - stat[:mean]) / stat[:stddev]
      next if z < ANOMALY_Z_THRESHOLD

      @anomalies << Anomaly.new(
        test_instance: test_instance, metric: metric, value: value,
        cohort_mean: stat[:mean], cohort_stddev: stat[:stddev],
        cohort_size: stat[:count], z_score: z, ratio: ratio
      )
    end
  end

  # Returns the count of open issues labeled `release-blocker` on the
  # MESAHub/mesa repo, or nil when we can't reach GitHub (no token, API
  # error, or running in the test environment). The view distinguishes
  # nil from 0 so subscribers can tell "couldn't check" apart from
  # "checked, nothing pending."
  def fetch_release_blocker_count
    return nil if Rails.env.test?
    return nil if ENV['GIT_TOKEN'].to_s.empty?

    Commit.api
          .issues(Commit.repo_path, labels: 'release-blocker', state: 'open')
          .length
  rescue StandardError
    nil
  end
end
