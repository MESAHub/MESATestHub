module CommitState
  extend ActiveSupport::Concern

  # Build status, derived from per-computer compile state across all
  # submissions for this commit.
  #
  #   :all_ok    every computer that submitted compiled
  #   :some_fail at least one computer failed to compile
  #   :all_fail  every computer failed (or no successful compile reported)
  #   :unknown   no submission has reported compilation either way
  #
  # "Per computer" because a single computer may submit several batches
  # for one commit (e.g., one per SDK). The computer's contribution to
  # the build aggregate is the OR of all its compiled flags — if any
  # of its submissions reports a successful compile, the computer counts
  # as built. This matches the spirit of Commit#computer_info: a row
  # there only renders a green tile if at least one submission compiled.
  def build_status
    stati = _build_stati_by_computer
    return :unknown if stati.empty?

    built = stati.count { |_id, ok| ok }
    failed = stati.count { |_id, ok| !ok }
    return :all_ok if failed.zero?
    return :all_fail if built.zero?
    :some_fail
  end

  # Tests status — a single token compact enough for a sparkline cell or
  # status pill, with worst-first prioritization. Aggregates over the
  # commit's test_case_commits.
  #
  #   :fail            ≥1 test case failed uniformly on every computer that ran it
  #   :mixed           ≥1 test case passed on some computers, failed on others
  #   :pending         work is in flight — at least one live claim is open
  #                    on this commit and the test side isn't done yet
  #   :pending_partial pending + some already passed
  #   :all_pass        every test case ran and passed
  #   :not_run         no tests ran AND no claims are open (genuinely
  #                    untouched — typically a brand-new commit or one
  #                    whose builds all failed)
  #
  # The `:pending` / `:not_run` split keys on `has_pending_claims?`,
  # not on "are there untested TCCs?". Before claims existed, the
  # only signal we had for "in flight" was "the TCC has no
  # submissions yet," which fires the instant a commit is ingested
  # — well before any computer has actually started work. Claims
  # are the real signal: a commit with no claims is genuinely
  # untouched, even if it has 500 TCCs sitting at status=-1.
  #
  # See app/models/test_case_commit.rb for the underlying status integer
  # vocabulary (-1 untested, 0 passing, 1 failing, 2 mixed_checksums,
  # 3 mixed).
  def tests_status
    counts = _test_case_status_counts

    has_uniform_fail = counts[:failing] > 0
    has_mixed        = counts[:mixed] > 0
    has_passing      = counts[:passing] > 0 || counts[:mixed_checksums] > 0
    has_pending      = counts[:untested] > 0 && has_pending_claims?

    case build_status
    when :all_fail, :unknown
      return :not_run if !has_passing && !has_uniform_fail && !has_mixed && !has_pending
    end

    return :fail if has_uniform_fail
    return :mixed if has_mixed
    return :pending if has_pending && !has_passing
    return :pending_partial if has_pending && has_passing
    return :all_pass if has_passing
    :not_run
  end

  # Counts of each design-level flag across all of this commit's test
  # instances. Returns a hash with three keys:
  #
  #   :fpe          — cells run with FPE checks enabled. Informational
  #                   only (like :inlists_full): it says how the test
  #                   was run, not that anything went wrong. Actual
  #                   FPE failures are :fpe_failure.
  #   :checksum     — cells whose checksum departs from the consensus
  #                   of instances that should agree bit-for-bit
  #                   (see ChecksumComparison).
  #   :inlists_full — passing instances run with run_optional=true
  #                   (exercised the full inlist set).
  #   :fpe_failure  — failing cells whose failures were all trapped
  #                   floating-point exceptions.
  #
  # These count *cells*. The hero tiles and index chips want *tests*
  # — see commit_state's `checksum_tests` / `fpe_tests`.
  def flag_counts
    matrix = test_computer_matrix
    counts = { fpe: 0, checksum: 0, inlists_full: 0, fpe_failure: 0, fpe_likely: 0 }
    matrix.each_value do |row|
      row.each_value do |cell|
        cell[:flags].each { |kind, on| counts[kind] += 1 if on }
      end
    end
    counts
  end

  # Aggregated state for this commit, shaped like
  # `getCommitState(sha)` from prototype/data.js. The view layer treats
  # this as a single input — pass it into pills, banners, the sparkline.
  def commit_state
    matrix = test_computer_matrix
    built_ids, failed_build_ids = _build_membership

    cells_by_test = matrix.transform_values do |row|
      row.select { |computer_id, _cell| built_ids.include?(computer_id) }
    end

    failing_cells = []
    mixed_cells = []
    uniform_failing_tests = 0
    mixed_tests = 0
    fpe_tests = 0
    checksum_tests = 0
    checksum_passing_tests = 0
    full_tests = 0
    pending_tests = 0
    passing_tests = 0

    pending_tcc_test_ids = _pending_claim_test_case_ids

    cells_by_test.each do |test_id, row|
      pendings = row.count { |_id, cell| cell[:status] == :pending }
      passes = row.count   { |_id, cell| cell[:status] == :pass }
      fails  = row.count   { |_id, cell| cell[:status] == :fail }
      fpe_fails = row.count { |_id, cell| cell[:status] == :fail && cell[:flags][:fpe_failure] }
      # Failures that weren't just a trapped FPE. An FPE-only test is
      # its own bucket rather than "failing"/"mixed".
      real_fails = fails - fpe_fails
      no_data = (pendings + passes + fails).zero?

      # Independent of the bucket below: a mixed test's passing
      # cells can still disagree on checksums.
      checksum_tests += 1 if row.any? { |_id, cell| cell[:flags][:checksum] }
      # Tests that at least one computer ran with the full inlist set.
      full_tests += 1 if row.any? { |_id, cell| cell[:flags][:inlists_full] }

      # Classification rule: "passing" = at least one computer ran and
      # passed AND nothing failed. Pending neighbors don't downgrade
      # the test; if some computers haven't submitted yet but every
      # one that did reported a pass, treat the test as passing. The
      # matrix view (which surfaces individual pending cells) is the
      # place to investigate "but did everyone really run it?"
      if real_fails.positive? && passes.positive?
        mixed_tests += 1
        row.each do |computer_id, cell|
          mixed_cells << { test_id: test_id, computer_id: computer_id } if cell[:status] == :fail
        end
      elsif real_fails.positive?
        # Any computer's fail makes the test failing — even when other
        # computers are still pending.
        uniform_failing_tests += 1
        row.each do |computer_id, cell|
          failing_cells << { test_id: test_id, computer_id: computer_id } if cell[:status] == :fail
        end
      elsif fpe_fails.positive?
        fpe_tests += 1
      elsif passes.positive?
        # Pass with no failures — the test is passing regardless of
        # pending neighbors.
        passing_tests += 1
        checksum_passing_tests += 1 if row.any? { |_id, cell| cell[:flags][:checksum] }
      elsif pendings.positive?
        # Cell-level pending: at least one built computer hasn't
        # reported a result yet. Counts as test-level pending
        # regardless of whether there's an explicit claim — the
        # build submission is the signal.
        pending_tests += 1
      elsif no_data && pending_tcc_test_ids.include?(test_id)
        # No cells (no built-computer is even attempting yet) AND
        # someone has claimed the test → genuine in-flight pending.
        pending_tests += 1
      end
      # no_data without a claim → not counted; the test is :not_run,
      # not :pending. Pre-claims this branch silently bucketed every
      # untouched test into pending_tests, which inflated the hero
      # tile for freshly-ingested commits and for builds-all-failed
      # commits that nobody's retrying.
    end

    has_uniform_fail = uniform_failing_tests.positive?
    has_mixed = mixed_tests.positive?
    has_pending = pending_tests.positive?

    # Worst-first. FPE failures are failures, so they outrank a
    # checksum divergence on otherwise-passing tests; both outrank
    # "still waiting on results".
    tests_token =
      if built_ids.empty? then :not_run
      elsif has_uniform_fail then :fail
      elsif has_mixed then :mixed
      elsif fpe_tests.positive? then :fpe
      elsif checksum_tests.positive? then :checksum
      elsif has_pending && passing_tests.zero? then :pending
      elsif has_pending then :pending_partial
      elsif passing_tests.positive? then :all_pass
      else :not_run
      end

    flags = flag_counts

    {
      build: {
        status: build_status,
        built_computer_ids: built_ids,
        failed_build_computer_ids: failed_build_ids
      },
      tests: {
        status: tests_token,
        uniform_failing_tests: uniform_failing_tests,
        mixed_tests: mixed_tests,
        fpe_tests: fpe_tests,
        checksum_tests: checksum_tests,
        full_tests: full_tests,
        pending_tests: pending_tests,
        passing_tests: passing_tests,
        # Passing tests with no checksum disagreement, and how many
        # tests have any pass/fail result at all — for the index's
        # status ring (segments + coverage).
        clean_passing_tests: passing_tests - checksum_passing_tests,
        # Otherwise-passing tests with a ≠ — the ring's disjoint
        # checksum bucket (checksum_tests also counts mixed/failing
        # tests whose passing runs disagree).
        checksum_passing_tests: checksum_passing_tests,
        reported_tests: uniform_failing_tests + mixed_tests + fpe_tests + passing_tests,
        total_tests: cells_by_test.size,
        failing_cells: failing_cells,
        mixed_cells: mixed_cells,
        has_uniform_fail: has_uniform_fail,
        has_mixed: has_mixed,
        has_pending: has_pending
      },
      flags: flags
    }
  end

  # Which tab to land on by default when a user opens the commit detail
  # page. Build issues steer them to Computers; test failures or mixed
  # results steer them to Tests; everything else lands on Summary. The
  # design re-applies this whenever the SHA changes, so the controller
  # picks here rather than expecting client-side logic.
  def default_detail_tab(state: nil)
    state ||= commit_state
    case state[:build][:status]
    when :all_fail, :some_fail
      :computers
    else
      # Test-side trouble (uniform fail, mixed, or pending) lands on
      # Summary — the matrix toolbar's worst-first default chip
      # (`default_matrix_filter`) takes the user straight to the
      # right slice of rows.
      :summary
    end
  end

  # Per-computer aggregate over the test×computer matrix. Returns one
  # hash per computer that submitted anything for this commit, sorted
  # worst-first so problem computers float to the top of the
  # Computers tab and the Summary sidebar.
  #
  #   { computer:, computer_id:, built:, state:,
  #     counts: { pass:, fail:, pending:, skip:, fpe:, checksum:, inlists_full: } }
  #
  # `state` is the worst-first symbol the row should render under:
  # :build_fail / :fail / :pending / :checksum (passing, but some
  # checksum disagrees with its comparison group) / :all_pass.
  def per_computer_summary
    matrix = test_computer_matrix
    built_ids, failed_ids = _build_membership
    all_subs = submissions.includes(computer: :user).to_a
    computers_by_id = all_subs.map(&:computer).uniq.index_by(&:id)
    subs_by_computer = all_subs.group_by(&:computer_id)

    rows = (built_ids + failed_ids).uniq.map do |computer_id|
      counts = { pass: 0, fail: 0, pending: 0, skip: 0,
                 fpe: 0, checksum: 0, inlists_full: 0, fpe_failure: 0, fpe_likely: 0 }

      matrix.each_value do |row|
        cell = row[computer_id]
        next unless cell
        counts[cell[:status]] += 1 if counts.key?(cell[:status])
        cell[:flags].each { |kind, on| counts[kind] += 1 if on }
      end

      built = built_ids.include?(computer_id)
      state =
        if !built then :build_fail
        elsif counts[:fail].positive? then :fail
        elsif counts[:pending].positive? then :pending
        elsif counts[:checksum].positive? then :checksum
        else :all_pass
        end

      {
        computer: computers_by_id[computer_id],
        computer_id: computer_id,
        built: built,
        state: state,
        counts: counts,
        submissions: subs_by_computer[computer_id] || []
      }
    end

    rows.sort_by { |r| [_computer_sort_rank(r[:state]), r[:computer]&.name.to_s] }
  end

  # Which checksum-comparison pool each computer's runs on this
  # commit mostly fall into, for grouping matrix columns. Mirrors the
  # ChecksumComparison split at the computer level: FPE-checking runs
  # (never compared) get their own pool; otherwise SDK vs. non-SDK
  # crossed with full vs. default runs. `run_optional` stands in for
  # inlist count here — close enough for a column layout, and the
  # cell flags still come from the exact per-instance comparison.
  #
  #   { computer_id => { pool: Symbol, mixed: Bool } }
  #
  # pool ∈ :sdk_default, :sdk_full, :other_default, :other_full,
  #        :fpe, :no_results. `mixed` is true when the computer's
  # runs straddle pools and it was placed by majority.
  def computer_pools
    @_computer_pools ||= begin
      by_computer = _tccs_for_matrix.flat_map { |tcc| tcc.test_instances.to_a }
                                    .group_by(&:computer_id)
      submissions.map(&:computer_id).uniq.each_with_object({}) do |cid, out|
        pools = (by_computer[cid] || []).map { |i| _instance_pool(i) }.tally
        if pools.empty?
          out[cid] = { pool: :no_results, mixed: false }
        else
          out[cid] = { pool: pools.max_by { |pool, n| [n, -COMPUTER_POOL_ORDER.index(pool)] }.first,
                       mixed: pools.size > 1 }
        end
      end
    end
  end

  COMPUTER_POOL_ORDER = %i[sdk_default sdk_full other_default other_full fpe no_results].freeze

  # The matrix's drawn columns. A computer whose runs on this commit
  # all fall in one comparison pool keeps a single column (key = its
  # id, so popover keys match the per-computer matrix). A computer
  # with runs in several pools — e.g. LLNL_Dane running every test
  # both default and full — gets one column per pool, so each cell
  # shows only runs that are compared with each other.
  #
  #   [{ key:, computer_id:, pool:, split: }, ...]  (unordered)
  def matrix_columns
    @_matrix_columns ||= begin
      pools = computer_pools
      by_computer = _instances_by_computer
      submissions.map(&:computer_id).uniq.flat_map do |cid|
        present = (by_computer[cid] || []).map { |i| _instance_pool(i) }.uniq
        if present.size > 1
          present.sort_by { |p| COMPUTER_POOL_ORDER.index(p) }.map do |pool|
            { key: "#{cid}-#{pool}", computer_id: cid, pool: pool, split: true }
          end
        else
          [{ key: cid.to_s, computer_id: cid, pool: pools.dig(cid, :pool) || :no_results, split: false }]
        end
      end
    end
  end

  # { test_case_id => { column_key => cell } } for matrix_columns.
  # Unsplit columns reuse the per-computer cell; split columns build a
  # cell from just that pool's runs (status :not_in_pool when the
  # computer didn't run this test that way). Every cell carries
  # `runs`, the number of instances behind it.
  def column_matrix
    @_column_matrix ||= begin
      matrix = test_computer_matrix
      subs_by_computer = submissions.group_by(&:computer_id)
      _tccs_for_matrix.each_with_object({}) do |tcc, out|
        row = out[tcc.test_case_id] = {}
        by_computer = tcc.test_instances.group_by(&:computer_id)
        matrix_columns.each do |col|
          all_runs = by_computer[col[:computer_id]] || []
          if col[:split]
            runs = all_runs.select { |i| _instance_pool(i) == col[:pool] }
            row[col[:key]] =
              if runs.empty?
                { status: :not_in_pool, flags: {}, runs: 0 }
              else
                _cell_for(tcc: tcc, computer_id: col[:computer_id], instances: runs,
                          submissions: subs_by_computer[col[:computer_id]] || [],
                          fpe_context: all_runs).merge(runs: runs.size)
              end
          else
            row[col[:key]] = (matrix.dig(tcc.test_case_id, col[:computer_id]) || { status: :no_build, flags: {} })
                               .merge(runs: all_runs.size)
          end
        end
      end
    end
  end

  # The instances behind one drawn column's cell for a test.
  def column_instances(tcc, col)
    runs = tcc.test_instances.select { |i| i.computer_id == col[:computer_id] }
    col[:split] ? runs.select { |i| _instance_pool(i) == col[:pool] } : runs
  end

  # Most recent earlier commit on which `computer` successfully
  # compiled. Used by the Computers tab to surface "last green build"
  # for a card whose build failed on this commit. Cross-branch by
  # design — what the user wants is "last time this computer compiled
  # anything," which is informational regardless of branch lineage.
  # Single LIMIT-1 query against the indexed `submissions.computer_id`.
  def last_successful_build_commit_for(computer)
    Submission.joins(:commit)
              .where(computer_id: computer.id, compiled: true)
              .where('commits.commit_time < ?', commit_time)
              .order('commits.commit_time DESC')
              .limit(1)
              .first&.commit
  end

  # Per-test aggregate over the test×computer matrix. Returns one hash
  # per test_case_commit, with the worst-first overall token, a row of
  # cells aligned by computer_id, and small counts. Feeds the Tests
  # tab's test-by-test rows.
  #
  #   { test_case:, test_case_commit:, overall:,
  #     cells_by_computer: { computer_id => cell }, counts: { pass:, fail:, ... } }
  #
  # `overall` ∈ { :fail, :mixed, :fpe, :checksum, :pending, :pass,
  # :not_run }. :fpe means every failure was a trapped floating-point
  # exception; :checksum means everything passed but some cell's
  # checksum disagrees with its comparison group.
  def per_test_summary
    matrix = test_computer_matrix
    built_ids, _ = _build_membership
    tccs_by_test = test_case_commits.includes(:test_case).index_by(&:test_case_id)

    rows = matrix.map do |test_id, row_cells|
      built_cells = row_cells.select { |cid, _| built_ids.include?(cid) }
      counts = { pass: 0, fail: 0, pending: 0, fpe: 0, checksum: 0, inlists_full: 0, fpe_failure: 0, fpe_likely: 0 }
      built_cells.each_value do |cell|
        counts[cell[:status]] += 1 if counts.key?(cell[:status])
        cell[:flags].each { |kind, on| counts[kind] += 1 if on }
      end

      # Mirrors the commit_state classification: any computer's pass
      # counts as the test passing as long as nothing failed and
      # nothing reported a checksum mismatch. Pending neighbors don't
      # downgrade; truly-unresolved tests (no pass anywhere) land in
      # :pending, and no-built-cell rows land in :not_run. FPE-only
      # failures get their own :fpe bucket.
      real_fails = counts[:fail] - counts[:fpe_failure]
      overall =
        if built_cells.empty? || (counts[:pass] + counts[:fail] + counts[:pending]).zero?
          :not_run
        elsif real_fails.positive? && counts[:pass].positive?
          :mixed
        elsif real_fails.positive?
          :fail
        elsif counts[:fpe_failure].positive?
          :fpe
        elsif counts[:pass].positive? && counts[:checksum].positive?
          :checksum
        elsif counts[:pass].positive?
          :pass
        elsif counts[:pending].positive?
          :pending
        else
          :not_run
        end

      tcc = tccs_by_test[test_id]
      {
        test_case: tcc&.test_case,
        test_case_commit: tcc,
        overall: overall,
        cells_by_computer: row_cells,
        counts: counts
      }
    end

    rows.compact.sort_by do |r|
      [
        _test_sort_rank(r[:overall]),
        _module_sort_rank(r[:test_case]&.module),
        r[:test_case]&.name.to_s
      ]
    end
  end

  # Compare this commit's matrix to another commit's matrix and return
  # the cells whose status got worse — used by the "Diff vs last pass"
  # tab. Each entry is `{ test_case_id:, computer_id:, change:, flag_kind?: }`
  # where `change` ∈ { :new_failure, :new_mixed, :new_flag } and
  # `flag_kind` is :checksum when change is :new_flag.
  #
  # "New failure" = cell was passing on `other` and is failing here.
  # "New mixed" = cell flipped from passing to mixed (the whole row's
  # state shifts, but we surface the changed cell).
  # "New flag" = cell stayed passing but picked up a checksum flag
  # (informational `inlists_full` / `fpe` are excluded — they say how
  # the test ran, not that it regressed).
  def cells_changed_since(other_commit)
    return [] unless other_commit

    other_matrix = other_commit.test_computer_matrix
    self_matrix = test_computer_matrix

    rows = []
    self_matrix.each do |test_id, this_row|
      prior_row = other_matrix[test_id] || {}
      this_row.each do |computer_id, cell|
        prior = prior_row[computer_id]
        next unless prior && prior[:status] == :pass

        if cell[:status] == :fail
          rows << { test_case_id: test_id, computer_id: computer_id,
                    change: :new_failure }
        elsif cell[:status] == :pass
          %i[checksum].each do |kind|
            if cell[:flags][kind] && !prior[:flags][kind]
              rows << { test_case_id: test_id, computer_id: computer_id,
                        change: :new_flag, flag_kind: kind }
            end
          end
        end
      end
    end

    rows
  end

  # The Tests×Computer cross-tab. Shape:
  #
  #   { test_case_id => { computer_id => { status: <Symbol>, flags: <Hash> } } }
  #
  # status ∈ { :pass, :fail, :pending, :skip, :no_build }
  # flags ∈ { fpe: Bool, checksum: Bool, inlists_full: Bool, fpe_failure: Bool }
  #
  # Computer axis: every computer that submitted anything for this
  # commit. Test axis: every test_case_commit (which itself records
  # which test cases ran on the commit's parent source layout).
  #
  # The aggregation is per-(test_case, computer) over test_instance
  # rows. If no instance exists for a (test_case, computer) pair but
  # the computer DID submit:
  #   * compiled → :pending (test scheduled, just not back yet)
  #   * !compiled → :no_build
  # If no submissions exist, the matrix has no row for that computer.
  # The commit-detail controller calls per_computer_summary,
  # per_test_summary, commit_state, and cell_popover_data on every
  # request, and each of those hits test_computer_matrix internally.
  # Memoizing on the instance pays for itself many times over for
  # the one HTTP request and is dropped when the instance goes out
  # of scope, so there's no cross-request staleness risk.
  def test_computer_matrix
    @_test_computer_matrix ||= _build_test_computer_matrix
  end

  # Popover-data hash keyed by `"#{test_id}-#{computer_id}"`. Every
  # cell that has a test_case + a real submission gets an entry — the
  # rail-anchored popover is the consistent click affordance, so even
  # a clean-pass cell wants a stub popover (test/computer/PASS/SDK +
  # link to the test page) rather than kicking the user out to a new
  # URL on click. The richer "interesting" fields (agreement,
  # checksum_match_*) only render for cells that aren't clean.
  #
  # The blob is rendered into a <script type="application/json"> tag
  # on the commit detail page and read by the popover Stimulus
  # controller on cell click.
  #
  # Per-cell shape (always present):
  #   test_name, module, computer_name, status, flags
  #   submission_count                  — # instances for (tcc, computer)
  #   latest                            — Hash with the most recent
  #                                       instance's failure_type
  #                                       (humanized), success_type,
  #                                       summary_text snippet,
  #                                       checksum, sdk_version,
  #                                       runtime_minutes, created_at
  #
  # Per-cell shape (only on non-clean cells):
  #   agreement                         — :single | :unanimous |
  #                                       :pass_fail_mixed | :checksum_mixed
  #   checksum_match_count / _total     — only when this cell carries
  #                                       a checksum flag; of the
  #                                       computers in the latest
  #                                       instance's comparison group,
  #                                       how many reported the same
  #                                       checksum (itself included)
  def cell_popover_data
    columns = matrix_columns
    col_matrix = column_matrix
    tccs = _tccs_for_matrix.index_by(&:test_case_id)
    computers_by_id = submissions.includes(:computer).map(&:computer).uniq.index_by(&:id)

    data = {}
    col_matrix.each do |test_id, row|
      tcc = tccs[test_id]
      next unless tcc
      tc = tcc.test_case
      next unless tc

      comparison = _checksum_comparison_for(tcc)
      all_by_computer = tcc.test_instances.group_by(&:computer_id)

      columns.each do |col|
        cell = row[col[:key]]
        next unless cell
        instances = column_instances(tcc, col)
        latest = instances.max_by { |i| [i.created_at || Time.at(0), i.id || 0] }

        entry = {
          test_name: tc.name,
          module: tc.module,
          computer_name: computers_by_id[col[:computer_id]]&.name,
          status: cell[:status],
          flags: cell[:flags],
          submission_count: instances.size
        }
        entry[:column_label] = COMPUTER_POOL_LABELS[col[:pool]] if col[:split]
        entry[:latest] = _popover_latest(latest) if latest
        unless _cell_clean?(cell)
          entry[:agreement] = _instance_agreement(instances, comparison)
          matches = cell[:flags][:checksum] && latest && comparison.match_counts(latest)
          if matches
            entry[:checksum_match_count] = matches[:count]
            entry[:checksum_match_total] = matches[:total]
          end
        end
        # Every run behind the cell, oldest first, once there's more
        # than one or a checksum disagreement to explain — so a
        # flag set by one run isn't hidden behind another's checksum.
        if instances.size > 1 || cell.dig(:flags, :checksum)
          context = all_by_computer[col[:computer_id]] || []
          entry[:runs] = instances.sort_by { |i| [i.created_at || Time.at(0), i.id || 0] }
                                  .map { |i| _popover_run(i, comparison, context) }
        end
        data["#{test_id}-#{col[:key]}"] = entry
      end
    end
    data
  end

  COMPUTER_POOL_LABELS = {
    sdk_default: "SDK · default inlists", sdk_full: "SDK · full inlists",
    other_default: "Non-SDK · default inlists", other_full: "Non-SDK · full inlists",
    fpe: "FPE checks on", no_results: "No results"
  }.freeze

  private

  # Memoize per-instance — `commit_state` calls both `build_status`,
  # `tests_status`, and `test_computer_matrix`, which all touch the
  # submissions association. The hash is cheap; the SELECTs aren't.
  def _build_stati_by_computer
    @_build_stati_by_computer ||= begin
      rows = submissions.pluck(:computer_id, :compiled)
      grouped = rows.group_by(&:first)
      # Test-by-test clients submit each result as a singleton submission
      # without an `entire`/`empty` flag, so the submissions controller
      # never records a `compiled` value (see SubmissionsController#create).
      # The aggregate used to drop those computers entirely, hiding their
      # results from the per-computer summary and the matrix. Submitting a
      # test result implies a successful build, so any computer with test
      # instances on this commit is implicitly built when no explicit
      # signal exists.
      implicit_built = test_instances.distinct.pluck(:computer_id).to_set
      grouped.each_with_object({}) do |(computer_id, computer_rows), out|
        flags = computer_rows.map(&:last).compact
        if flags.empty?
          out[computer_id] = true if implicit_built.include?(computer_id)
        else
          out[computer_id] = flags.any? { |ok| ok }
        end
      end
    end
  end

  def _build_membership
    stati = _build_stati_by_computer
    built = stati.select { |_id, ok| ok }.keys
    failed = stati.reject { |_id, ok| ok }.keys
    [built, failed]
  end

  def _test_case_status_counts
    counts = { untested: 0, passing: 0, failing: 0, mixed_checksums: 0, mixed: 0 }
    test_case_commits.pluck(:status).each do |s|
      case s
      when -1 then counts[:untested] += 1
      when 0 then counts[:passing] += 1
      when 1 then counts[:failing] += 1
      when 2 then counts[:mixed_checksums] += 1
      when 3 then counts[:mixed] += 1
      end
    end
    counts
  end

  def _build_test_computer_matrix
    tccs = _tccs_for_matrix
    submissions_by_computer = submissions.group_by(&:computer_id)
    computer_ids = submissions_by_computer.keys

    test_ids = tccs.map(&:test_case_id)

    matrix = {}
    test_ids.each { |tid| matrix[tid] = {} }

    tccs.each do |tcc|
      instances_by_computer = tcc.test_instances.group_by(&:computer_id)

      computer_ids.each do |cid|
        matrix[tcc.test_case_id][cid] = _cell_for(
          tcc: tcc,
          computer_id: cid,
          instances: instances_by_computer[cid] || [],
          submissions: submissions_by_computer[cid] || []
        )
      end
    end

    matrix
  end

  # Cached for the lifetime of the Commit instance. Same eager-loaded
  # association set used by the matrix and popover-data passes.
  # `pending_claims` is included so the row-classification loop in
  # `commit_state` can ask each TCC "is anyone actually working on
  # you?" without firing a query per test case.
  def _tccs_for_matrix
    @_tccs_for_matrix ||= test_case_commits
                            .includes(:test_case, :test_instances, :pending_claims)
                            .to_a
  end

  # `test_case_id` set for every TCC on this commit that currently
  # has a pending test-scope claim. Used in the row-classification
  # loop in `commit_state` to distinguish "no data on this test
  # because no one is working on it" (counts as :not_run) from "no
  # data on this test because the work is still in flight" (counts
  # as :pending).
  def _pending_claim_test_case_ids
    @_pending_claim_test_case_ids ||= _tccs_for_matrix
                                        .select(&:has_pending_claims?)
                                        .map(&:test_case_id)
                                        .to_set
  end

  # A cell is "clean" (no agreement detail in the popover) iff it
  # passed without a checksum disagreement. FPE-checks and full-inlist
  # runs are informational, not problems.
  def _cell_clean?(cell)
    cell[:status] == :pass && !(cell[:flags] || {})[:checksum]
  end

  # One ChecksumComparison per TCC, memoized for the request — the
  # matrix, popover data, and summaries all ask the same question.
  def _checksum_comparison_for(tcc)
    @_checksum_comparisons ||= {}
    @_checksum_comparisons[tcc.id] ||= tcc.checksum_comparison
  end

  def _instance_agreement(instances, comparison)
    return :single if instances.size <= 1
    passes = instances.count(&:passed)
    fails = instances.size - passes
    return :pass_fail_mixed if passes.positive? && fails.positive?
    # This computer's own runs disagree with each other (disagreeing
    # with other computers is what the ≠ flag and "N/M match" say).
    return :checksum_mixed if instances.select(&:passed).map(&:checksum).reject(&:blank?).uniq.size > 1
    :unanimous
  end

  # One run's line in a cell popover's run list.
  def _popover_run(instance, comparison, same_computer_runs)
    matches = comparison.match_counts(instance)
    {
      created_at: instance.created_at&.iso8601,
      passed: instance.passed,
      variant: instance.run_optional ? "full" : "default",
      fpe_checks: !!instance.fpe_checks,
      inlists: instance.inlist_count,
      failure_type: instance.failure_type && TestInstance.failure_types[instance.failure_type],
      fpe_failure: TestInstance.fpe_failure_kind(instance, same_computer_runs),
      checksum: instance.checksum.presence&.slice(0, 7),
      match: matches && "#{matches[:count]}/#{matches[:total]}",
      disagrees: comparison.disagrees?(instance)
    }.compact
  end

  def _popover_latest(instance)
    summary = instance.summary_text.to_s.strip
    summary = summary[0, 400] + (summary.length > 400 ? "…" : "") if summary.length > 400
    {
      passed: instance.passed,
      success_type: instance.success_type && TestInstance.success_types[instance.success_type],
      failure_type: instance.failure_type && TestInstance.failure_types[instance.failure_type],
      summary_text: summary.presence,
      checksum: instance.checksum,
      sdk_version: instance.sdk_version,
      runtime_minutes: instance.runtime_minutes,
      created_at: instance.created_at&.iso8601
    }.compact
  end

  # `fpe_context` is every run this computer made of the test (defaults
  # to `instances`); split matrix columns pass it so a failure in the
  # FPE column can still be judged against the same computer's
  # FPE-off run in another column.
  def _cell_for(tcc:, computer_id:, instances:, submissions:, fpe_context: nil)
    base_flags = { fpe: false, checksum: false, inlists_full: false, fpe_failure: false, fpe_likely: false }

    if instances.empty?
      status =
        if submissions.empty? then :no_build
        elsif submissions.any? { |s| s.compiled == true } then :pending
        else :no_build
        end
      return { status: status, flags: base_flags }
    end

    passed = instances.count(&:passed)
    failed = instances.size - passed

    status =
      if passed.positive? && failed.zero? then :pass
      elsif failed.positive? && passed.zero? then :fail
      else :fail # mixed at instance level still surfaces as :fail in the matrix
      end

    # `inlists_full` and `fpe` describe how the test was *run*, not
    # whether it ended in a pass — a failing test that ran the full
    # inlist set still carries that signal. `checksum` is set only on
    # cells holding an instance that disagrees with its comparison
    # group — not on every passing cell of a row with a mismatch.
    flags = base_flags.dup
    flags[:inlists_full] = instances.any? { |i| i.run_optional }
    flags[:fpe]          = instances.any? { |i| i.fpe_checks }
    flags[:checksum]     = instances.any? { |i| _checksum_comparison_for(tcc).disagrees?(i) }
    # Every failing run here tripped a floating-point exception —
    # reported by MESA, or inferred from this computer passing the
    # same test with FPE checks off (see TestInstance.fpe_failure_kind).
    flags.merge!(_fpe_flags(instances, fpe_context || instances))

    { status: status, flags: flags }
  end

  def _fpe_flags(instances, context)
    failures = instances.reject(&:passed)
    kinds = failures.map { |f| TestInstance.fpe_failure_kind(f, context) }
    all_fpe = failures.any? && kinds.all?
    { fpe_failure: all_fpe, fpe_likely: all_fpe && kinds.include?(:likely) }
  end

  def _instances_by_computer
    @_instances_by_computer ||= _tccs_for_matrix.flat_map { |tcc| tcc.test_instances.to_a }
                                                .group_by(&:computer_id)
  end

  def _instance_pool(instance)
    return :fpe if instance.fpe_checks
    toolchain = instance.sdk_version.present? ? 'sdk' : 'other'
    :"#{toolchain}_#{instance.run_optional ? 'full' : 'default'}"
  end

  def _computer_sort_rank(state)
    { build_fail: 0, fail: 1, pending: 2, checksum: 3, all_pass: 4 }.fetch(state, 5)
  end

  def _test_sort_rank(overall)
    # :not_run sits next to :pending — both mean "we don't have an
    # answer yet" — so they cluster together in the Tests-tab list
    # rather than getting hidden after the all-pass section.
    { fail: 0, mixed: 1, fpe: 2, checksum: 3, pending: 4, not_run: 5, pass: 6 }.fetch(overall, 7)
  end

  # Sort tests by `TestCase.modules` order — star → binary → astero
  # at time of writing. Sourcing the ranking from `TestCase.modules`
  # (rather than e.g. inverting an alphabetical compare) means the
  # order survives if MESA adds a new module like `eos` that
  # doesn't sit at the end of the alphabet.
  def _module_sort_rank(mod_name)
    TestCase.modules.index(mod_name.to_s) || TestCase.modules.size
  end
end
