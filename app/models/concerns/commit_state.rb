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

      pending_tests += 1 if pendings.positive?

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
end
