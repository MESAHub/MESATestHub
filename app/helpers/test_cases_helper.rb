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
end
