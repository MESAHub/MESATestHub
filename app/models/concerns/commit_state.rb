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
  #   :pending         test runs are still going, nothing passing yet
  #   :pending_partial pending + some already passed
  #   :all_pass        every test case ran and passed
  #   :not_run         no tests ran (typically because all builds failed)
  #
  # See app/models/test_case_commit.rb for the underlying status integer
  # vocabulary (-1 untested, 0 passing, 1 failing, 2 mixed_checksums,
  # 3 mixed).
  def tests_status
    counts = _test_case_status_counts

    has_uniform_fail = counts[:failing] > 0
    has_mixed = counts[:mixed] > 0
    has_pending = counts[:untested] > 0
    has_passing = counts[:passing] > 0 || counts[:mixed_checksums] > 0

    case build_status
    when :all_fail, :unknown
      return :not_run if !has_passing && !has_uniform_fail && !has_mixed
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
  #   :fpe          — passing instances run with FPE checks enabled.
  #                   The design wants "FPE raised during run, test
  #                   still passed numerically"; the schema doesn't
  #                   surface that signal explicitly, so we use
  #                   fpe_checks=true on passing instances as a proxy
  #                   until the model evolves.
  #   :checksum     — passing instances whose owning test_case_commit
  #                   has more than one unique checksum across
  #                   computers (bit-for-bit reproducibility broken,
  #                   per the design).
  #   :inlists_full — passing instances run with run_optional=true
  #                   (exercised the full inlist set).
  def flag_counts
    matrix = test_computer_matrix
    counts = { fpe: 0, checksum: 0, inlists_full: 0 }
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
    pending_tests = 0
    passing_tests = 0

    cells_by_test.each do |test_id, row|
      pendings = row.count { |_id, cell| cell[:status] == :pending }
      passes = row.count   { |_id, cell| cell[:status] == :pass }
      fails  = row.count   { |_id, cell| cell[:status] == :fail }
      ran = passes + fails
      # "Never run" — no built-computer cell has reported any result.
      # Treat the same as pending so the hero's stat row + the Tests
      # tab reflect that the test is *missing* a result, not passing.
      # Happens when no computer compiled (so the matrix filter to
      # built_ids leaves the row empty) or when a built computer
      # hasn't gotten around to submitting test data yet.
      not_run = (pendings + passes + fails).zero?

      pending_tests += 1 if pendings.positive? || not_run

      if fails.positive? && passes.positive?
        mixed_tests += 1
        row.each do |computer_id, cell|
          mixed_cells << { test_id: test_id, computer_id: computer_id } if cell[:status] == :fail
        end
      elsif fails.positive? && fails == ran
        uniform_failing_tests += 1
        row.each do |computer_id, cell|
          failing_cells << { test_id: test_id, computer_id: computer_id } if cell[:status] == :fail
        end
      elsif passes.positive? && passes == ran && pendings.zero?
        passing_tests += 1
      end
    end

    has_uniform_fail = uniform_failing_tests.positive?
    has_mixed = mixed_tests.positive?
    has_pending = pending_tests.positive?

    tests_token =
      if built_ids.empty? then :not_run
      elsif has_uniform_fail then :fail
      elsif has_mixed then :mixed
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
        pending_tests: pending_tests,
        passing_tests: passing_tests,
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
      if state[:tests][:has_uniform_fail] || state[:tests][:has_mixed]
        :tests
      else
        :summary
      end
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
  # :build_fail / :fail / :pending / :mixed (flagged-but-passing) /
  # :all_pass.
  def per_computer_summary
    matrix = test_computer_matrix
    built_ids, failed_ids = _build_membership
    computers_by_id = submissions.includes(computer: :user)
                                 .map(&:computer).uniq.index_by(&:id)

    rows = (built_ids + failed_ids).uniq.map do |computer_id|
      counts = { pass: 0, fail: 0, pending: 0, skip: 0,
                 fpe: 0, checksum: 0, inlists_full: 0 }

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
        elsif counts[:fpe].positive? || counts[:checksum].positive? then :mixed
        else :all_pass
        end

      {
        computer: computers_by_id[computer_id],
        computer_id: computer_id,
        built: built,
        state: state,
        counts: counts
      }
    end

    rows.sort_by { |r| [_computer_sort_rank(r[:state]), r[:computer]&.name.to_s] }
  end

  # Per-test aggregate over the test×computer matrix. Returns one hash
  # per test_case_commit, with the worst-first overall token, a row of
  # cells aligned by computer_id, and small counts. Feeds the Tests
  # tab's test-by-test rows.
  #
  #   { test_case:, test_case_commit:, overall:,
  #     cells_by_computer: { computer_id => cell }, counts: { pass:, fail:, ... } }
  #
  # `overall` ∈ { :fail, :mixed, :pending, :flagged, :pass } — :flagged
  # means everything passed but at least one cell carries an fpe or
  # checksum flag. :flagged renders under the warning color (same as
  # :mixed) in the design.
  def per_test_summary
    matrix = test_computer_matrix
    built_ids, _ = _build_membership
    tccs_by_test = test_case_commits.includes(:test_case).index_by(&:test_case_id)

    rows = matrix.map do |test_id, row_cells|
      built_cells = row_cells.select { |cid, _| built_ids.include?(cid) }
      counts = { pass: 0, fail: 0, pending: 0, fpe: 0, checksum: 0, inlists_full: 0 }
      built_cells.each_value do |cell|
        counts[cell[:status]] += 1 if counts.key?(cell[:status])
        cell[:flags].each { |kind, on| counts[kind] += 1 if on }
      end
      ran = counts[:pass] + counts[:fail]

      # A built-computer row that has no pass/fail/pending counts at
      # all means the test was never run on any computer that
      # compiled — render as :not_run so the Tests tab shows a gray
      # dot instead of misleading green.
      overall =
        if built_cells.empty? || (counts[:pass] + counts[:fail] + counts[:pending]).zero?
          :not_run
        elsif counts[:fail].positive? && counts[:pass].positive? then :mixed
        elsif counts[:fail].positive? && counts[:fail] == ran then :fail
        elsif counts[:pending].positive? then :pending
        elsif (counts[:fpe] + counts[:checksum]).positive? then :flagged
        else :pass
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
  # `flag_kind` is :fpe or :checksum when change is :new_flag.
  #
  # "New failure" = cell was passing on `other` and is failing here.
  # "New mixed" = cell flipped from passing to mixed (the whole row's
  # state shifts, but we surface the changed cell).
  # "New flag" = cell stayed passing but picked up an fpe or checksum
  # flag (informational `inlists_full` is excluded — it isn't a
  # regression).
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
          %i[fpe checksum].each do |kind|
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
  # flags ∈ { fpe: Bool, checksum: Bool, inlists_full: Bool }
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
  def test_computer_matrix
    tccs = test_case_commits.includes(:test_case, :test_instances).to_a
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

  private

  # Memoize per-instance — `commit_state` calls both `build_status`,
  # `tests_status`, and `test_computer_matrix`, which all touch the
  # submissions association. The hash is cheap; the SELECTs aren't.
  def _build_stati_by_computer
    @_build_stati_by_computer ||= begin
      rows = submissions.pluck(:computer_id, :compiled)
      grouped = rows.group_by(&:first)
      grouped.each_with_object({}) do |(computer_id, computer_rows), out|
        flags = computer_rows.map(&:last).compact
        next if flags.empty?
        out[computer_id] = flags.any? { |ok| ok }
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

  def _cell_for(tcc:, computer_id:, instances:, submissions:)
    base_flags = { fpe: false, checksum: false, inlists_full: false }

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

    flags = base_flags.dup
    if status == :pass
      flags[:inlists_full] = instances.any? { |i| i.run_optional }
      flags[:fpe] = instances.any? { |i| i.fpe_checks }
      flags[:checksum] = tcc.checksum_count.to_i > 1
    end

    { status: status, flags: flags }
  end

  def _computer_sort_rank(state)
    { build_fail: 0, fail: 1, pending: 2, mixed: 3, all_pass: 4 }.fetch(state, 5)
  end

  def _test_sort_rank(overall)
    # :not_run sits next to :pending — both mean "we don't have an
    # answer yet" — so they cluster together in the Tests-tab list
    # rather than getting hidden after the all-pass section.
    { fail: 0, mixed: 1, pending: 2, not_run: 3, flagged: 4, pass: 5 }.fetch(overall, 6)
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
