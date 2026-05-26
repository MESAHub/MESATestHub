# Builds the data structure for the daily MESA Test Hub digest email.
# Both MorningMailer and MorningMailerController consume one of these.
#
# A report covers a 24-hour test window ending at `as_of` (defaults to now).
# It groups commits-tested-during-the-window by branch (main first), captures
# their pass/fail/mixed/checksum scalars, and flags individual passing test
# instances whose runtime or RAM is anomalously high compared to the cohort
# of recent passing runs on the same (test_case, computer, run_optional,
# fpe_checks) combination.
#
# Build the report through `MorningReport.for(date:)` — the result is cached
# in `Rails.cache` for 24 hours so the web preview and the actual email
# render the same numbers without re-computing the expensive aggregations.
class MorningReport
  WINDOW = 24.hours

  # Cohort math knobs. The cohort is the previous `COHORT_LIMIT` passing
  # instances on the same (test_case, computer, run_optional, fpe_checks)
  # — anything older or in a different cohort is irrelevant.
  COHORT_LIMIT = 50
  COHORT_MIN_SIZE = 8        # need at least this many samples for stats
  ANOMALY_Z_THRESHOLD = 3.0  # require >= 3 sigma above cohort mean
  ANOMALY_RATIO_FLOOR = 1.25 # AND >= 25% above cohort mean (protects
                             # against tiny-stddev cohorts where 3σ is
                             # still a meaningless absolute jump)

  attr_reader :date, :window_start, :window_end, :branch_sections,
              :anomalies, :countdown_days, :release_blocker_count

  def self.for(date: Date.current, force: false)
    cache_key = "morning_report:#{date.iso8601}"
    Rails.cache.delete(cache_key) if force
    Rails.cache.fetch(cache_key, expires_in: 24.hours) do
      new(as_of: date.end_of_day).tap(&:build)
    end
  end

  def initialize(as_of: Time.current)
    @window_end = as_of
    @window_start = as_of - WINDOW
    @date = as_of.to_date
    @branch_sections = []
    @anomalies = []
  end

  def build
    load_commits
    load_anomalies
    load_meta
    self
  end

  # All commits in the window, regardless of branch. Useful for callers
  # that want a flat list (e.g. anomaly cohort lookups).
  def commits_tested
    @commits_tested ||= []
  end

  def any_commits?
    commits_tested.any?
  end

  def any_failing?
    branch_sections.any? { |section| section.failing? }
  end

  def any_anomalies?
    anomalies.any?
  end

  # ===== Inner data classes =====

  # Stand-in for a real Branch on synthetic BranchSections. Must be a
  # *named* constant so Marshal-based caching can serialize it
  # (Rails.cache.write → Marshal.dump refuses anonymous classes).
  SyntheticBranch = Struct.new(:name)

  # One branch's worth of commits-tested-in-window, in commit_time DESC.
  # `synthetic` is true for the catch-all "Unattached commits" group
  # built from commits that have no branch memberships — typically PR
  # test-merge commits or commits whose membership row hasn't synced yet.
  BranchSection = Struct.new(:branch, :commit_summaries, :synthetic,
                             keyword_init: true) do
    def failing?
      commit_summaries.any?(&:failing?)
    end

    def commit_count
      commit_summaries.size
    end

    # Branch name to use when building per-commit URLs. Synthetic
    # sections don't have a real branch route, so fall back to main —
    # the commit detail page accepts any branch name and uses it
    # only as nav context.
    def link_branch_name
      synthetic ? "main" : branch.name
    end
  end

  # Per-commit roll-up.
  #
  # `status` mirrors `Commit#status` (the test rollup):
  #   -1 = untested / rollup not finalized (CI run in progress)
  #    0 = passing, 1 = failing, 2 = checksums, 3 = mixed
  #
  # `build_status` mirrors `Commit#compilation_status` (compile rollup):
  #   -1 = no compile status reported
  #    0 = compiles everywhere, 1 = fails everywhere, 2 = mixed
  #
  # `computer_count` is the count of distinct (computer × spec)
  # submissions on this commit.  `complete_computer_count` is how
  # many of those actually ran all test cases.  Drive-by submitters
  # that ran 1/106 tests still bump `computer_count` but not
  # `complete_computer_count`, so the digest reports both.
  CommitSummary = Struct.new(
    :commit, :status, :build_status, :tested_count,
    :computer_count, :complete_computer_count,
    :failing_tccs, :checksum_tccs, :mixed_tccs, :passing_count,
    keyword_init: true
  ) do
    def status_label
      case status
      when 0 then :passing
      when 1 then :failing
      when 2 then :checksums
      when 3 then :mixed
      else :untested
      end
    end

    def build_label
      case build_status
      when 0 then :build_ok
      when 1 then :build_fail
      when 2 then :build_mixed
      else :build_none
      end
    end

    def failing?
      status_label == :failing || status_label == :mixed ||
        build_label == :build_fail || build_label == :build_mixed
    end

    def problem_tccs
      failing_tccs + checksum_tccs + mixed_tccs
    end
  end

  # One flagged metric on one test instance.  `metric` is one of
  # :total_runtime, :rn_runtime, :re_runtime, :rn_mem, :re_mem.
  Anomaly = Struct.new(
    :test_instance, :metric, :value, :cohort_mean, :cohort_stddev,
    :cohort_size, :z_score, :ratio,
    keyword_init: true
  ) do
    METRIC_LABEL = {
      total_runtime: 'Total runtime',
      rn_runtime: 'rn runtime',
      re_runtime: 're runtime',
      rn_mem: 'rn RAM',
      re_mem: 're RAM'
    }.freeze

    METRIC_UNIT = {
      total_runtime: 's',
      rn_runtime: 's',
      re_runtime: 's',
      rn_mem: 'GB',
      re_mem: 'GB'
    }.freeze

    def memory?
      metric == :rn_mem || metric == :re_mem
    end

    def label
      METRIC_LABEL[metric]
    end

    def unit
      METRIC_UNIT[metric]
    end

    # Memory metrics live in kB on the DB; display as GB.
    def display_value
      memory? ? value.to_f / (1024.0 * 1024.0) : value.to_f
    end

    def display_mean
      memory? ? cohort_mean / (1024.0 * 1024.0) : cohort_mean
    end
  end

  private

  def load_commits
    instances_in_window = TestInstance
      .where(created_at: window_start..window_end)
      .where.not(commit_id: nil)
    commit_ids = instances_in_window.pluck(:commit_id).uniq
    return if commit_ids.empty?

    commits = Commit
      .where(id: commit_ids)
      .includes(test_case_commits: :test_case,
                branch_memberships: :branch)
      .order(commit_time: :desc)
    @commits_tested = commits.to_a

    # Group commits by branch — a commit may belong to multiple.
    # Commits with no branch memberships (PR test-merge commits and
    # in-flight pushes whose membership row hasn't synced) collect
    # into an "unattached" bucket that renders as a synthetic
    # section after the real branches.
    branch_to_commits = Hash.new { |h, k| h[k] = [] }
    unattached_commits = []
    commits.each do |commit|
      memberships = commit.branch_memberships
      if memberships.empty?
        unattached_commits << commit
      else
        memberships.each { |bm| branch_to_commits[bm.branch] << commit }
      end
    end

    ordered_branches = branch_to_commits.keys
    main = Branch.main
    if main && (i = ordered_branches.index { |b| b.id == main.id })
      ordered_branches.unshift(ordered_branches.delete_at(i))
    end

    @branch_sections = ordered_branches.map do |branch|
      BranchSection.new(
        branch: branch,
        commit_summaries: branch_to_commits[branch].map { |c| build_summary(c) },
        synthetic: false
      )
    end

    if unattached_commits.any?
      @branch_sections << BranchSection.new(
        branch: SyntheticBranch.new("Unattached commits"),
        commit_summaries: unattached_commits.map { |c| build_summary(c) },
        synthetic: true
      )
    end
  end

  def build_summary(commit)
    tccs = commit.test_case_commits.to_a
    CommitSummary.new(
      commit: commit,
      status: commit.status,
      build_status: commit.compilation_status,
      tested_count: commit.passed_count.to_i + commit.failed_count.to_i +
                    commit.mixed_count.to_i + commit.checksum_count.to_i,
      computer_count: commit.computer_count.to_i,
      complete_computer_count: commit.complete_computer_count.to_i,
      passing_count: commit.passed_count.to_i,
      failing_tccs: tccs.select { |t| t.status == 1 },
      checksum_tccs: tccs.select { |t| t.status == 2 },
      mixed_tccs: tccs.select { |t| t.status == 3 }
    )
  end

  def load_anomalies
    return if commits_tested.empty?

    candidates = TestInstance
      .where(commit_id: commits_tested.map(&:id), passed: true)
      .where.not(runtime_seconds: nil)
      .includes(:test_case, :computer, :commit)

    return if candidates.empty?

    # Group by cohort key — one batched stats query per group.
    candidates_by_key = candidates.group_by { |ti| cohort_key(ti) }

    candidates_by_key.each do |key, group|
      stats = cohort_stats(key, oldest: group.map { |ti| ti.commit.commit_time }.min)
      next unless stats

      group.each { |ti| flag_anomalies(ti, stats) }
    end

    # Within a (commit, test_case, computer) cell, keep at most the worst
    # offender across metrics to avoid duplicate-ish noise.
    @anomalies = dedupe_anomalies(@anomalies)
  end

  def cohort_key(ti)
    [ti.test_case_id, ti.computer_id, ti.run_optional, ti.fpe_checks]
  end

  # Returns a hash of metric -> {mean: x, stddev: y, count: n} for the
  # cohort of the previous COHORT_LIMIT passing instances matching the
  # key, observed strictly before `oldest` (so we never compare a
  # candidate to itself or to its same-day siblings).
  def cohort_stats(key, oldest:)
    test_case_id, computer_id, run_optional, fpe_checks = key

    cohort = TestInstance
      .joins(:commit)
      .where(test_case_id: test_case_id,
             computer_id: computer_id,
             run_optional: run_optional,
             fpe_checks: fpe_checks,
             passed: true)
      .where('commits.commit_time < ?', oldest)
      .order('commits.commit_time DESC')
      .limit(COHORT_LIMIT)

    rows = cohort.pluck(:runtime_seconds, :re_time, :total_runtime_seconds,
                        :mem_rn, :mem_re)
    return nil if rows.size < COHORT_MIN_SIZE

    {
      rn_runtime: column_stats(rows, 0),
      re_runtime: column_stats(rows, 1),
      total_runtime: column_stats(rows, 2),
      rn_mem: column_stats(rows, 3),
      re_mem: column_stats(rows, 4)
    }
  end

  def column_stats(rows, idx)
    values = rows.map { |r| r[idx] }.compact
    return nil if values.size < COHORT_MIN_SIZE

    mean = values.sum.to_f / values.size
    variance = values.sum { |v| (v - mean)**2 } / values.size.to_f
    { mean: mean, stddev: Math.sqrt(variance), count: values.size }
  end

  METRIC_TO_COLUMN = {
    rn_runtime: :runtime_seconds,
    re_runtime: :re_time,
    total_runtime: :total_runtime_seconds,
    rn_mem: :mem_rn,
    re_mem: :mem_re
  }.freeze

  def flag_anomalies(test_instance, stats)
    METRIC_TO_COLUMN.each do |metric, column|
      stat = stats[metric]
      next unless stat

      value = test_instance.public_send(column)
      next if value.nil? || value.zero?
      next if stat[:mean].zero?

      ratio = value.to_f / stat[:mean]
      next if ratio < ANOMALY_RATIO_FLOOR

      z = stat[:stddev].zero? ? Float::INFINITY :
                                (value - stat[:mean]) / stat[:stddev]
      next if z < ANOMALY_Z_THRESHOLD

      @anomalies << Anomaly.new(
        test_instance: test_instance,
        metric: metric,
        value: value,
        cohort_mean: stat[:mean],
        cohort_stddev: stat[:stddev],
        cohort_size: stat[:count],
        z_score: z,
        ratio: ratio
      )
    end
  end

  # Sort worst-first; keep at most one anomaly per (test_instance, metric).
  # If the same test instance has separate metrics flagged we keep both.
  def dedupe_anomalies(list)
    by_key = {}
    list.each do |a|
      k = [a.test_instance.id, a.metric]
      existing = by_key[k]
      by_key[k] = a if existing.nil? || a.z_score > existing.z_score
    end
    by_key.values.sort_by { |a| -a.z_score }
  end

  def load_meta
    @countdown_days = nil    # placeholder; release-date countdown can be
                             # repopulated when there's a real upcoming
                             # release date to count down to.
    @release_blocker_count = fetch_release_blocker_count
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
