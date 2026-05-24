module TestCasesHelper
  # Build a test_case_path URL preserving the current branch / module /
  # name / tab / window / center, with `overrides` merged on top. Used
  # by the time-window toolbar so its size chips, pan arrows, and
  # picker forms each surgically change one knob without dropping the
  # others.
  #
  # Center encoding: pass `:center` to override; pass `center: nil`
  # explicitly to clear it (jump to HEAD).
  #
  # NOTE: the URL param is `center`, not `anchor`, because Rails'
  # `url_for` treats `:anchor` as the URL fragment (#...). See the
  # controller's `resolve_anchor_commit` for the longer explanation.
  def toolbar_path(overrides = {})
    base = {
      branch:    @selected_branch.name,
      module:    @test_case.module,
      test_case: @test_case.name,
      tab:       @active_tab,
      window:    @window_size,
      center:    params[:center].presence
    }
    test_case_path(base.merge(overrides).compact)
  end

  # Tabs on the test_cases#show page. Helper-resident so the HAML
  # partial doesn't trip the "multi-line Ruby in attribute hash" gotcha
  # (see CLAUDE.md — array literals can't span lines inside a `- …`
  # block in HAML).
  TAB_SPECS = [
    [:history,     "History"],
    [:trend,       "Trend"],
    [:submissions, "Submissions"]
  ].freeze

  def show_tab_specs
    TAB_SPECS
  end

  # Status chips for the headline's Tier-2 counts row. Returns
  # [label, count, dot_class, text_color_class] tuples. Same
  # multi-line-array reason as `show_tab_specs`.
  def headline_status_chips(counts)
    [
      ["passing",  counts[:passing],  "bg-success", "text-success-soft-text"],
      ["failing",  counts[:failing],  "bg-danger",  "text-danger-soft-text"],
      ["mixed",    counts[:mixed],    "bg-warning", "text-warning-soft-text"],
      ["checksum", counts[:checksum], "bg-warning", "text-warning-soft-text"],
      ["untested", counts[:untested], "bg-skipped", "text-fg-muted"]
    ]
  end

  # Segmented-control specs for the History tab's status filter.
  # `entries` is the window's [{ commit:, tcc:, status: }, ...]
  # array; counts come from the in-window slice so the chip numbers
  # match what the user actually sees.
  def history_status_specs_for_entries(entries)
    by_status = entries.each_with_object(Hash.new(0)) { |e, h| h[e[:status]] += 1 }
    [
      ["all",      "All",      entries.size,  nil],
      ["failing",  "Failing",  by_status[1],  "bg-danger"],
      ["mixed",    "Mixed",    by_status[3],  "bg-warning"],
      ["checksum", "Checksum", by_status[2],  "bg-warning"],
      ["passing",  "Passing",  by_status[0],  "bg-success"],
      ["untested", "Untested", by_status[-1], "bg-skipped"]
    ]
  end

  # Mapping from TCC status integer to the string the History row's
  # status filter chips reference. Kept in sync with the chip ids
  # above.
  def history_row_filter(status)
    case status
    when 0  then "passing"
    when 1  then "failing"
    when 2  then "checksum"
    when 3  then "mixed"
    else         "untested"
    end
  end

  # Build the popover payload for the History tab matrix. One entry
  # per (commit, computer) pair where there's something worth saying.
  # Clean-pass-no-flags cells get NO entry — the Stimulus popover
  # controller falls back to a direct navigation to the test-on-commit
  # page in that case (see popover_controller.js#open).
  #
  # Returns a flat hash keyed by `"#{commit.id}-#{computer_name}"`
  # so the cell trigger's `data-popover-key` can look up its info in
  # one shot.
  #
  # Each entry carries the commit-centric header fields the popover
  # controller expects (commit_sha, commit_short_sha, commit_message,
  # commit_author, commit_time_ago) plus the standard cell payload
  # (status, flags, latest, submission_count, agreement) and a
  # `metrics` block with the scalar values the user investigates
  # when chasing degradation in a passing test (steps, retries,
  # redos, solver_iterations, log_rel_run_E_err, runtime, RAM).
  #
  # 250 commits × ~7 computers ≈ 1750 cells worst-case. Skipping
  # clean cells typically drops this by 60-80% — the payload size
  # stays comfortably under ~100 KB even at the widest window.
  def history_popover_data(entries, test_case:, branch:)
    payload = {}
    entries.each do |entry|
      tcc    = entry[:tcc]
      commit = entry[:commit]
      next unless tcc

      by_computer = tcc.test_instances.group_by { |ti| ti.computer&.name }
      by_computer.each do |name, instances|
        next if name.nil?
        cell = _popover_cell_state(tcc, instances)
        next if _popover_clean?(cell)

        latest = instances.max_by { |i| [i.created_at || Time.at(0), i.id || 0] }
        key = "#{commit.id}-#{name}"
        payload[key] = {
          test_name:     test_case.name,
          module:        test_case.module,
          computer_name: name,
          commit_sha:    commit.sha,
          commit_short_sha: commit.short_sha,
          commit_message: commit.message_first_line(80),
          commit_author: commit.author,
          commit_time_ago: time_ago_compact(commit.commit_time),
          test_case_commit_href: test_case_commit_path(branch: branch.name,
                                                       sha: commit.short_sha,
                                                       module: test_case.module,
                                                       test_case: test_case.name,
                                                       computer: name),
          status: cell[:status],
          flags:  cell[:flags],
          submission_count: instances.size,
          agreement: _popover_agreement(instances),
          latest:  _popover_latest_instance(latest),
          metrics: _popover_metrics(latest)
        }.compact
      end
    end
    payload
  end

  # Build the per-page per-computer matrix payload for the History
  # tab. Returns:
  #
  #   {
  #     columns: ["bertha", "pleiades", ...],   # sorted computer names
  #     cells:   { tcc_id => { computer_name => cell_hash } }
  #   }
  #
  # where `cell_hash` matches the shape `_matrix_cell_visual` expects:
  # `{ status: :pass | :fail | nil, flags: { fpe:, checksum:, inlists_full: } }`.
  # Missing (tcc, computer) pairs simply aren't present in the inner
  # hash — the view layer treats `nil` lookups as "no data" cells.
  #
  # Assumes the rows arrived with `test_instances: :computer` eager
  # loaded (TestCase#history_window does this), so no per-cell DB
  # hits.
  def history_matrix_payload(rows)
    columns = Set.new
    cells = {}

    rows.each do |tcc|
      tcc.test_instances.each do |ti|
        name = ti.computer&.name
        next unless name

        columns << name
        cells[tcc.id] ||= {}
        existing = cells[tcc.id][name]
        cells[tcc.id][name] = merge_cell(existing, ti, tcc)
      end
    end

    { columns: columns.to_a.sort, cells: cells }
  end

  # Status word + Tailwind text-color class for the History row's
  # status pill. Mirrors `tcc_status_word` / `tcc_status_dot_class`
  # from `TestCaseCommitsHelper` but returns the *text-color* class
  # the row uses next to the SHA.
  def history_row_status(status)
    case status
    when 1  then ["failing",  "text-danger-soft-text"]
    when 3  then ["mixed",    "text-warning-soft-text"]
    when 2  then ["checksum-divergent", "text-warning-soft-text"]
    when 0  then ["passing",  "text-success-soft-text"]
    when -1 then ["untested", "text-fg-muted"]
    else         ["unknown",  "text-fg-muted"]
    end
  end

  private

  # Combine an existing cell (if any) with another test_instance for
  # the same (tcc, computer). Worst-result wins for `status` (so a
  # mix of pass + fail surfaces as :fail); flags OR together so a
  # checksum mismatch flagged on any one instance carries through.
  def merge_cell(existing, ti, tcc)
    new_status = ti.passed ? :pass : :fail
    status = if existing.nil?
               new_status
             elsif existing[:status] == :fail || new_status == :fail
               :fail
             else
               :pass
             end
    base_flags = existing&.dig(:flags) || { fpe: false, checksum: false, inlists_full: false }
    flags = {
      fpe:           base_flags[:fpe]           || !!ti.fpe_checks,
      checksum:      base_flags[:checksum]      || tcc.checksum_count.to_i > 1,
      inlists_full:  base_flags[:inlists_full]  || !!ti.run_optional
    }
    { status: status, flags: flags }
  end

  # Cell-state computation for the popover specifically — agrees with
  # the visual matrix cell but recomputed here because the visual
  # cell hash isn't kept after rendering.
  def _popover_cell_state(tcc, instances)
    base_flags = { fpe: false, checksum: false, inlists_full: false }
    return { status: :no_build, flags: base_flags } if instances.empty?

    passed = instances.count(&:passed)
    failed = instances.size - passed
    status =
      if passed.positive? && failed.zero? then :pass
      elsif failed.positive? && passed.zero? then :fail
      else :fail
      end
    flags = {
      fpe:          instances.any? { |i| i.fpe_checks },
      checksum:     passed.positive? && tcc.checksum_count.to_i > 1,
      inlists_full: instances.any? { |i| i.run_optional }
    }
    { status: status, flags: flags }
  end

  def _popover_clean?(cell)
    cell[:status] == :pass && (cell[:flags] || {}).values.none? { |v| v }
  end

  def _popover_agreement(instances)
    return :single if instances.size <= 1
    passes = instances.count(&:passed)
    fails = instances.size - passes
    return :pass_fail_mixed if passes.positive? && fails.positive?
    checksums = instances.select(&:passed).map(&:checksum).compact.uniq
    return :checksum_mixed if checksums.size > 1
    :unanimous
  end

  def _popover_latest_instance(instance)
    summary = instance.summary_text.to_s.strip
    summary = summary[0, 400] + (summary.length > 400 ? "…" : "") if summary.length > 400
    {
      passed: instance.passed,
      success_type: instance.success_type && TestInstance.success_types[instance.success_type],
      failure_type: instance.failure_type && TestInstance.failure_types[instance.failure_type],
      summary_text: summary.presence,
      checksum: instance.checksum,
      sdk_version: instance.sdk_version,
      runtime_minutes: instance.runtime_minutes
    }.compact
  end

  # The reason this view exists — scalar metrics across commits so a
  # user can spot "steps tripled" or "retries shot up" in a passing
  # test that's degrading. Keeps numeric types intact so the popover
  # can render with appropriate precision.
  def _popover_metrics(instance)
    {
      runtime_minutes:        instance.runtime_minutes,
      mem_rn_gb:              (instance.rn_mem_GB if instance.respond_to?(:rn_mem_GB) && instance.mem_rn),
      threads:                instance.omp_num_threads,
      steps:                  instance.steps,
      retries:                instance.retries,
      redos:                  instance.redos,
      solver_iterations:      instance.solver_iterations,
      solver_calls_made:      instance.solver_calls_made,
      solver_calls_failed:    instance.solver_calls_failed,
      log_rel_run_E_err:      instance.log_rel_run_E_err
    }.compact
  end
end
