# Decides what a computer should work on next: which commit to build
# (`scope: 'build'`), or which test to run on a commit it has built
# (`scope: 'test'`), and with which run-time switches (full inlists,
# FPE checks, converge). Backs POST /api/v1/dispatch. Read-only — the
# client registers intent separately via POST /api/v1/claims.
#
# The algorithm (docs/dispatcher-and-claims.md, "Recommendation
# algorithm") in brief:
#
#   * Candidates: commits from the last 30 days, on main or an
#     unmerged branch active in the last 90 days, not `[ci skip]`,
#     and not blocklisted for this computer.
#   * Build: skip commits this computer already submitted on or holds
#     a pending build claim for; score the rest by branch, recency,
#     coverage by other computers, and unmet CI requests it can serve.
#   * Test: on the pinned commit (or the best-scoring commit this
#     computer built in the last week), pick the test that most needs a run —
#     unmet CI configurations first, then fewest computers.
#
#   WorkDispatcher.new(computer:, scope: 'build',
#                      capabilities: { full_inlists: true }).call
#   # => WorkDispatcher::Recommendation or nil
#
# Coefficients are V1 placeholders, to be tuned against real traffic.
class WorkDispatcher
  CANDIDATE_WINDOW     = 30.days
  ACTIVE_BRANCH_WINDOW = 90.days
  # Unpinned test dispatch only revisits builds this recent, so a
  # computer isn't sent back to finish weeks-old commits it skipped
  # tests on.
  RECENT_BUILD_WINDOW  = 7.days

  MAIN_WEIGHT      = 10
  BRANCH_WEIGHT    = 5
  RECENCY_WEIGHT   = 10
  # Coverage penalty: the first other computer on a commit costs more
  # than each one after it, so a commit with one computer still beats
  # a stale untested one — we want at least two platforms on every
  # main commit (checksum comparison needs a second opinion).
  FIRST_COVERAGE_PENALTY = 5
  MORE_COVERAGE_PENALTY  = 2
  CI_BOOST         = 5

  # Run-time configurations a commit can request, keyed the way the
  # API spells them (`can_<config>` in, `use_<config>` out). Each maps
  # to the Commit columns behind the request and the message tag.
  CONFIGS = {
    full_inlists: { wants: :wants_full_inlists, satisfied: :full_inlists_satisfied_at,
                    tag: '[ci optional]' },
    fpe:          { wants: :wants_fpe, satisfied: :fpe_satisfied_at, tag: '[ci fpe]' },
    converge:     { wants: :wants_converge, satisfied: :converge_satisfied_at,
                    tag: '[ci converge]' }
  }.freeze

  Recommendation = Struct.new(:commit, :scope, :test_case_commit, :flags,
                              :score, :reasons, keyword_init: true) do
    # The API's `use_*` flag hash.
    def flag_params
      flags.transform_keys { |config| :"use_#{config}" }
    end
  end

  # One scored candidate commit. `reasons` are human-readable and
  # surface in the API response for debugging.
  Scored = Struct.new(:commit, :score, :reasons)

  def initialize(computer:, scope:, commit: nil, capabilities: {}, now: Time.current)
    raise ArgumentError, "unknown scope #{scope.inspect}" unless Claim::SCOPES.include?(scope)
    raise ArgumentError, 'a pinned commit only applies to scope test' if commit && scope == 'build'

    @computer = computer
    @scope = scope
    @pinned_commit = commit
    @can = CONFIGS.keys.index_with { |config| !!capabilities[config] }
    @now = now
  end

  def call
    @scope == 'build' ? recommend_build : recommend_test
  end

  private

  # ---------------------------------------------------------------- build

  def recommend_build
    ids = candidate_commit_ids
    ids -= Submission.where(computer: @computer, commit_id: ids).distinct.pluck(:commit_id)
    ids -= Claim.pending.where(computer: @computer, scope: 'build', commit_id: ids)
                .pluck(:commit_id)
    best = score_commits(ids).first
    return nil unless best

    # The build's modes apply to a whole-suite run (e.g. cluster array jobs
    # running `mesa_test test N`), so the same one-mode-per-run rule as test
    # dispatch: FPE plus at most one run-time mode.
    wanted = one_run_of(CONFIGS.keys.select { |config| commit_wants?(best.commit, config) })
    flags = CONFIGS.keys.index_with { |config| wanted.include?(config) }
    Recommendation.new(commit: best.commit, scope: 'build', test_case_commit: nil,
                       flags: flags, score: best.score.round(2), reasons: best.reasons)
  end

  # ----------------------------------------------------------------- test

  def recommend_test
    scored = if @pinned_commit
               [Scored.new(@pinned_commit, nil, ['pinned to the requested commit'])]
             else
               score_commits(built_commit_ids(candidate_commit_ids))
             end

    scored.each do |candidate|
      pick = best_test_on(candidate.commit)
      next unless pick

      tcc, needed, coverage, = pick
      reasons = candidate.reasons.dup
      reasons += needed.map { |config| "#{CONFIGS[config][:tag]} not yet run for this test" }
      reasons << coverage_reason(coverage, 'this test')
      return Recommendation.new(commit: candidate.commit, scope: 'test', test_case_commit: tcc,
                                flags: CONFIGS.keys.index_with { |c| needed.include?(c) },
                                score: candidate.score&.round(2), reasons: reasons)
    end
    nil
  end

  # Commits (from `ids`) this computer has built recently: it has a
  # submission from the last RECENT_BUILD_WINDOW whose `compiled`
  # isn't explicitly false. Singleton per-test submissions leave
  # `compiled` nil, and running a test implies a build.
  def built_commit_ids(ids)
    Submission.where(computer: @computer, commit_id: ids)
              .where(created_at: (@now - RECENT_BUILD_WINDOW)..)
              .where('compiled IS NULL OR compiled = TRUE')
              .distinct.pluck(:commit_id)
  end

  # The most-needed eligible test on `commit` for this computer, as
  # [tcc, configs_to_run_now, other_computer_count, configs_outstanding],
  # or nil when there is nothing left for it to run there.
  def best_test_on(commit)
    tccs = commit.test_case_commits.includes(:test_case).to_a
    return nil if tccs.empty?

    runs = TestInstance.where(commit_id: commit.id)
                       .pluck(:test_case_commit_id, :computer_id,
                              *CONFIGS.keys.map { |c| Arel.sql(Commit::CI_RUN_CONDITIONS[c]) })
                       .group_by(&:first)
    claims = Claim.pending.where(commit_id: commit.id, scope: 'test')
                  .pluck(:test_case_commit_id, :computer_id, :use_full_inlists,
                         :use_fpe, :use_converge)
                  .group_by(&:first)
    blocked = blocklisted_claims.where(scope: 'test', commit_id: commit.id)
                                .pluck(:test_case_commit_id).to_set

    ranked = tccs.filter_map do |tcc|
      next if blocked.include?(tcc.id)
      tcc_runs = runs[tcc.id] || []
      tcc_claims = claims[tcc.id] || []
      next if tcc_claims.any? { |row| row[1] == @computer.id }

      needed = CONFIGS.keys.select.with_index do |config, i|
        commit_requests?(commit, config) &&
          tcc_runs.none? { |row| row[2 + i] } &&
          tcc_claims.none? { |row| row[2 + i] }
      end
      ran_here = tcc_runs.any? { |row| row[1] == @computer.id }
      next if ran_here && needed.empty?

      coverage = ((tcc_runs.map { |row| row[1] } | tcc_claims.map { |row| row[1] }) -
                  [@computer.id]).size
      [tcc, one_run_of(needed), coverage, needed.size]
    end

    ranked.min_by do |tcc, _asked, coverage, outstanding|
      [-outstanding, coverage, tcc.test_case.module.to_s, tcc.test_case.name.to_s]
    end
  end

  # ------------------------------------------------------------ candidates

  # Commit ids eligible for dispatch to this computer, before any
  # scope-specific filtering.
  def candidate_commit_ids
    Commit.where(commit_time: (@now - CANDIDATE_WINDOW)..@now, ci_skip: false)
          .where(id: BranchMembership.where(branch_id: active_branch_ids).select(:commit_id))
          .where.not(id: blocklisted_claims.where(scope: 'build').select(:commit_id))
          .pluck(:id)
  end

  # Main, plus unmerged branches whose head landed recently.
  def active_branch_ids
    Branch.joins(:head)
          .where("branches.name = 'main' OR " \
                 '(branches.merged = FALSE AND commits.commit_time >= ?)',
                 @now - ACTIVE_BRANCH_WINDOW)
          .pluck(:id)
  end

  # Claims this computer let expire without ever submitting — the one
  # signal that the work genuinely failed. A late submission removes
  # the claim from this set automatically. Build claims block the whole
  # commit; test claims block only their test.
  def blocklisted_claims
    Claim.expired.where(computer: @computer).where.missing(:submission)
  end

  # Score commits by id, best first. Coverage counts *other* computers
  # that have submitted on, or hold a pending build claim for, each
  # commit.
  def score_commits(ids)
    return [] if ids.empty?

    commits = Commit.where(id: ids).to_a
    main = Branch.main
    on_main = main ? BranchMembership.where(branch_id: main.id, commit_id: ids)
                                     .pluck(:commit_id).to_set : Set.new
    coverers = Hash.new { |h, k| h[k] = Set.new }
    Submission.where(commit_id: ids).where.not(computer_id: @computer.id)
              .distinct.pluck(:commit_id, :computer_id)
              .each { |cid, comp| coverers[cid] << comp }
    Claim.pending.where(commit_id: ids, scope: 'build').where.not(computer_id: @computer.id)
         .distinct.pluck(:commit_id, :computer_id)
         .each { |cid, comp| coverers[cid] << comp }

    commits.map do |commit|
      reasons = []
      score = 0.0

      if on_main.include?(commit.id)
        score += MAIN_WEIGHT
        reasons << 'on main'
      else
        score += BRANCH_WEIGHT
        reasons << 'on an active branch'
      end

      age_days = (@now - commit.commit_time) / 1.day
      score += RECENCY_WEIGHT * [1 - age_days / CANDIDATE_WINDOW.in_days, 0].max
      reasons << "#{age_days.floor} day(s) old"

      coverage = coverers[commit.id].size
      score -= coverage_penalty(coverage)
      reasons << coverage_reason(coverage, 'this commit')

      CONFIGS.each do |config, spec|
        next unless commit_wants?(commit, config)
        score += CI_BOOST
        reasons << "#{spec[:tag]} not yet satisfied"
      end

      Scored.new(commit, score, reasons)
    end.sort_by { |s| [-s.score, -s.commit.commit_time.to_f, s.commit.sha] }
  end

  def coverage_penalty(count)
    return 0 if count.zero?
    FIRST_COVERAGE_PENALTY + MORE_COVERAGE_PENALTY * (count - 1)
  end

  # What to ask for in a single test run, given the configurations a test
  # still needs: FPE (a property of the whole build, so it costs nothing
  # extra) plus at most one run-time mode. A full-inlists run at a
  # converge resolution factor answers neither request cleanly — and is
  # excluded from checksum comparison — so a test needing both gets two
  # runs, on successive dispatches.
  def one_run_of(needed)
    needed.select { |c| c == :fpe } + needed.reject { |c| c == :fpe }.first(1)
  end

  # The commit asks for `config` and this computer can do it.
  def commit_requests?(commit, config)
    @can[config] && commit.public_send(CONFIGS[config][:wants])
  end

  # ...and nobody has covered the whole commit that way yet.
  def commit_wants?(commit, config)
    commit_requests?(commit, config) && commit.public_send(CONFIGS[config][:satisfied]).nil?
  end

  def coverage_reason(count, subject)
    return "no other computer on #{subject} yet" if count.zero?
    "#{count} other computer#{'s' unless count == 1} on #{subject}"
  end
end
