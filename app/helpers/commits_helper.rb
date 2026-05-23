module CommitsHelper
  # Inline SVG icons matching the design's stroke-only set (16x16,
  # stroke-width 1.5, currentColor). Tailwind's `text-*` utilities
  # color these.
  ICON_PATHS = {
    check: '<path d="M3 8.5l3.5 3.5L13 5.5"/>'.html_safe,
    x: '<path d="M4 4l8 8M12 4l-8 8"/>'.html_safe,
    branch: '<circle cx="5" cy="3" r="1.5"/><circle cx="5" cy="13" r="1.5"/><circle cx="11" cy="8" r="1.5"/><path d="M5 4.5v7M5 9c0-2 3-2 3-3.5"/>'.html_safe,
    chevron: '<path d="M4 6l4 4 4-4"/>'.html_safe,
    arrow_left: '<path d="M11 8H3M3 8l4-4M3 8l4 4"/>'.html_safe,
    arrow_right: '<path d="M3 8h9M12 8l-4-4M12 8l-4 4"/>'.html_safe,
    search: '<circle cx="7" cy="7" r="4"/><path d="M10 10l3 3"/>'.html_safe,
    clock: '<circle cx="8" cy="8" r="6"/><path d="M8 4.5V8l2.5 1.5"/>'.html_safe,
    eye_off: '<path d="M2 8s2-4 6-4 6 4 6 4-2 4-6 4-6-4-6-4zM2 2l12 12"/>'.html_safe,
    warn: '<path d="M8 2l6 11H2l6-11zM8 7v3M8 11.5v.01"/>'.html_safe,
    wrench: '<path d="M10.5 1.5a3 3 0 014 4l-1.5 1.5-1-1 1.2-1.2a1.5 1.5 0 00-2.1-2.1L10 3.8l-1-1 1.5-1.3zM9 5l5 5-3 3-5-5 3-3zM5.5 8.5l-3 3a1 1 0 001.4 1.4l3-3"/>'.html_safe,
    neq: '<path d="M3 6h10M3 10h10"/><path d="M11 3l-6 10"/>'.html_safe,
    plus: '<path d="M8 3v10M3 8h10"/>'.html_safe,
    file: '<path d="M4 2h5l3 3v9H4z"/><path d="M9 2v3h3"/>'.html_safe,
    github: '<path d="M8 1.5C4.4 1.5 1.5 4.4 1.5 8c0 2.9 1.9 5.3 4.4 6.2.3.1.4-.1.4-.3v-1.2c-1.8.4-2.2-.8-2.2-.8-.3-.7-.7-.9-.7-.9-.6-.4 0-.4 0-.4.6 0 1 .7 1 .7.6 1 1.6.7 2 .6.1-.4.2-.7.4-.9-1.4-.2-2.9-.7-2.9-3.2 0-.7.3-1.3.7-1.7-.1-.2-.3-.9.1-1.8 0 0 .6-.2 1.8.7.5-.1 1.1-.2 1.6-.2.6 0 1.1.1 1.6.2 1.2-.8 1.8-.7 1.8-.7.4.9.1 1.6.1 1.8.4.4.7 1 .7 1.7 0 2.5-1.5 3-2.9 3.2.2.2.4.6.4 1.2v1.8c0 .2.1.4.4.3 2.6-.9 4.4-3.3 4.4-6.2 0-3.6-2.9-6.5-6.5-6.5z"/>'.html_safe,
    copy: '<rect x="5" y="5" width="9" height="9" rx="1.5"/><path d="M3 11V3a1 1 0 011-1h7"/>'.html_safe,
    download: '<path d="M8 2v8M4.5 6.5L8 10l3.5-3.5M3 13h10"/>'.html_safe
  }.freeze

  def mesa_icon(name, size: 16, css: nil)
    paths = ICON_PATHS[name] or return ""
    content_tag(:svg,
                paths,
                viewBox: "0 0 16 16",
                width: size,
                height: size,
                fill: "none",
                stroke: "currentColor",
                "stroke-width": "1.5",
                "stroke-linecap": "round",
                "stroke-linejoin": "round",
                "aria-hidden": "true",
                class: css)
  end

  # Worst-first dot color for a commit state. The design's "blue =
  # running" was repurposed in review: we don't model a "promised but
  # not yet submitted" state, so blue now means *incomplete* (some
  # tests passed, others have no submission), and "everything
  # untested" collapses into the gray (`:skipped`) bucket alongside
  # commits whose builds wiped out tests entirely.
  def status_dot_class(state)
    tests = state[:tests][:status]
    return "bg-buildfail" if state[:build][:status] == :all_fail
    return "bg-danger"    if state[:tests][:has_uniform_fail]
    return "bg-warning"   if state[:tests][:has_mixed] || state[:build][:status] == :some_fail
    return "bg-info"      if tests == :pending_partial
    return "bg-skipped"   if tests == :pending || tests == :not_run
    "bg-success"
  end

  # Renders the build-status pill: All built / Partial / Build failed.
  def build_status_pill(state, size: :md)
    base = pill_classes(size)
    case state[:build][:status]
    when :all_fail
      content_tag(:span, class: "#{base} bg-buildfail-soft text-buildfail-soft-text") do
        safe_join([mesa_icon(:x, size: 11), "Build failed"], " ")
      end
    when :some_fail
      built = state[:build][:built_computer_ids].size
      failed = state[:build][:failed_build_computer_ids].size
      content_tag(:span, class: "#{base} bg-warning-soft text-warning-soft-text") do
        safe_join([mesa_icon(:warn, size: 11), "#{failed} of #{built + failed} not built"], " ")
      end
    when :unknown
      content_tag(:span, class: "#{base} bg-bg-muted text-fg-muted") do
        safe_join([mesa_icon(:eye_off, size: 11), "No build data"], " ")
      end
    else
      content_tag(:span, class: "#{base} bg-success-soft text-success-soft-text") do
        safe_join([mesa_icon(:check, size: 11), "All built"], " ")
      end
    end
  end

  # Renders the test-status pill: All passing / N failing / N mixed /
  # Pending / Untested.
  #
  # Mapping note: `:pending` (TCCs exist, no submissions) and
  # `:not_run` (no test data at all) both render as gray "Untested"
  # since the codebase doesn't model a "promised but not yet
  # submitted" distinction. Blue is reserved for `:pending_partial`
  # — some test cases have passing submissions, others haven't
  # reported — which is genuinely actionable. The word stays
  # "Pending" because we don't actually know whether the run is in
  # flight, queued, or lost; "Pending" is the honest framing.
  def test_status_pill(state, size: :md)
    base = pill_classes(size)
    case state[:tests][:status]
    when :not_run, :pending
      content_tag(:span, class: "#{base} bg-bg-muted text-fg-muted") do
        safe_join([mesa_icon(:eye_off, size: 11), "Untested"], " ")
      end
    when :fail
      content_tag(:span, class: "#{base} bg-danger-soft text-danger-soft-text") do
        safe_join([mesa_icon(:x, size: 11), "#{state[:tests][:uniform_failing_tests]} failing"], " ")
      end
    when :mixed
      content_tag(:span, class: "#{base} bg-warning-soft text-warning-soft-text") do
        safe_join([mesa_icon(:warn, size: 11), "#{state[:tests][:mixed_tests]} mixed"], " ")
      end
    when :pending_partial
      content_tag(:span, class: "#{base} bg-info-soft text-info-soft-text") do
        safe_join([mesa_icon(:clock, size: 11), "Pending"], " ")
      end
    else
      content_tag(:span, class: "#{base} bg-success-soft text-success-soft-text") do
        safe_join([mesa_icon(:check, size: 11), "All passing"], " ")
      end
    end
  end

  # Renders the inline flag chips for a commit (fpe / checksum / inlists_full).
  def flag_chips(state)
    flags = state[:flags]
    chips = []
    if flags[:fpe].to_i > 0
      chips << content_tag(:span,
                           safe_join([mesa_icon(:wrench, size: 10), "#{flags[:fpe]} FPE"], " "),
                           class: "#{pill_classes(:sm)} bg-warning-soft text-warning-soft-text",
                           title: "FPE checks raised on #{flags[:fpe]} runs")
    end
    if flags[:checksum].to_i > 0
      chips << content_tag(:span,
                           safe_join([mesa_icon(:neq, size: 10), "#{flags[:checksum]} ≠"], " "),
                           class: "#{pill_classes(:sm)} bg-warning-soft text-warning-soft-text",
                           title: "Checksum diverged across computers")
    end
    if flags[:inlists_full].to_i > 0
      chips << content_tag(:span,
                           safe_join([mesa_icon(:plus, size: 10), "#{flags[:inlists_full]} full"], " "),
                           class: "#{pill_classes(:sm)} bg-info-soft text-info-soft-text",
                           title: "Full inlist sets exercised")
    end
    return content_tag(:span, "—", class: "text-fg-subtle") if chips.empty?
    safe_join(chips, content_tag(:span, " ", class: "inline-block w-1"))
  end

  # Small label-over-value block used in the commit detail hero's
  # stat row. Label is uppercase 11px; value is 22px/600. `color` is
  # a Tailwind text-* utility class applied to the value.
  def stat_block(label:, value:, color: "text-fg")
    content_tag(:div, class: "min-w-0") do
      safe_join([
        content_tag(:span, label, class: "mesa-label mb-1"),
        content_tag(:span, value,
                    class: "block font-semibold tabular-nums #{color}",
                    style: "font-size: 22px; letter-spacing: -0.4px; line-height: 1.1;")
      ])
    end
  end

  # Extract a PR number from a commit message of the form
  # "Subject line (#1234)" or "(#1234) Subject" — MESA uses the
  # trailing-parens form. Returns the integer or nil.
  def commit_pr_number(commit)
    match = commit.message.to_s.match(/\(#(\d+)\)/)
    match && match[1].to_i
  end

  # Triage per_test rows into the three buckets the Summary matrix
  # cares about: rows where any built-computer cell isn't a clean
  # pass (the "interesting" rows to show), rows where every built
  # cell is a clean pass (hidden), and rows with no built cells at
  # all (also hidden, counted separately so the caption can read
  # "Hiding X clean and Y not yet run"). Built here as a helper so
  # the partial doesn't drag a multi-line case dispatch through
  # HAML's one-statement-per-line constraint.
  def matrix_partition(per_test, built_computer_ids)
    interesting = []
    clean_count = 0
    not_run_count = 0
    built_set = built_computer_ids.to_set
    per_test.each do |row|
      built_cells = (row[:cells_by_computer] || {}).select do |cid, _|
        built_set.include?(cid)
      end
      if built_cells.empty?
        not_run_count += 1
      elsif built_cells.values.all? { |c| c[:status] == :pass && c[:flags].none? { |_, v| v } }
        clean_count += 1
      else
        interesting << row
      end
    end
    [interesting, clean_count, not_run_count]
  end

  # Visual attributes for a Test × Computer matrix cell. Returns a
  # hash the `_matrix_cell` partial uses to render the cell without
  # bringing the dispatching logic into HAML. Encoding follows the
  # design handoff's table of cell states (see
  # `docs/design_handoff_mesa_testhub/README.md` → "Test×Computer
  # matrix"). Key shape:
  #
  #   kind:        :solid | :striped — controls background pattern.
  #   bg:          primary fill (a `var(--color-…)` string).
  #   stripe:      secondary stripe color for :striped cells.
  #   glyph:       optional centered icon name (:x, :neq, :wrench,
  #                :clock, :check).
  #   glyph_color: color for the glyph (usually white on solids).
  #   corner:      optional corner-badge icon name (:plus, :wrench).
  #   corner_bg:   background for the corner badge.
  #   label:       short text used as the cell's `title` tooltip.
  def matrix_cell_attrs(cell)
    return { kind: :solid, bg: "var(--color-bg-muted)", label: "no data" } unless cell

    flags = cell[:flags] || {}
    case cell[:status]
    when :no_build
      { kind: :striped,
        bg: "var(--color-bg-subtle)",
        stripe: "var(--color-bg-muted)",
        label: "build failed — test not run" }
    when :pending
      { kind: :striped,
        bg: "var(--color-info-soft)",
        stripe: "var(--color-info)",
        glyph: :clock,
        glyph_color: "var(--color-info-soft-text)",
        label: "pending" }
    when :fail
      label_parts = ["fail"]
      label_parts << "FPE" if flags[:fpe]
      label_parts << "full inlists" if flags[:inlists_full]
      label = label_parts.join(" · ")
      # Failing cells can still carry "this was a full-inlist run"
      # or "FPE checks were enabled" signals — the test was *run*
      # under those conditions even though it ended in a fail. The
      # corner badge surfaces that; the main glyph stays the X
      # since the headline result is still a failure.
      corner = if flags[:inlists_full] then :plus
               elsif flags[:fpe] then :wrench
               end
      attrs = { kind: :solid,
                bg: "var(--color-danger)",
                glyph: :x,
                glyph_color: "white",
                label: label }
      if corner
        attrs[:corner] = corner
        attrs[:corner_bg] = "var(--color-info)"
      end
      attrs
    when :pass
      label_parts = ["pass"]
      label_parts << "FPE" if flags[:fpe]
      label_parts << "checksum ≠" if flags[:checksum]
      label_parts << "full inlists" if flags[:inlists_full]
      label = label_parts.join(" · ")

      if flags[:fpe] && flags[:checksum]
        { kind: :solid, bg: "var(--color-warning)", glyph: :neq, glyph_color: "white",
          corner: :wrench, corner_bg: "var(--color-warning-soft-text)", label: label }
      elsif flags[:checksum]
        corner = flags[:inlists_full] ? :plus : nil
        { kind: :solid, bg: "var(--color-warning)", glyph: :neq, glyph_color: "white",
          corner: corner, corner_bg: "var(--color-info)", label: label }
      elsif flags[:fpe]
        corner = flags[:inlists_full] ? :plus : nil
        { kind: :solid, bg: "var(--color-warning)", glyph: :wrench, glyph_color: "white",
          corner: corner, corner_bg: "var(--color-info)", label: label }
      elsif flags[:inlists_full]
        { kind: :solid, bg: "var(--color-success)",
          corner: :plus, corner_bg: "var(--color-info)", label: label }
      else
        { kind: :solid, bg: "var(--color-success)", label: label }
      end
    else
      { kind: :solid, bg: "var(--color-skipped)", label: cell[:status].to_s }
    end
  end

  # Tailwind background class for a per-computer status dot in the
  # Summary sidebar / Computers tab. Mirrors the worst-first colors
  # used elsewhere.
  def status_dot_class_for_computer(state)
    case state
    when :build_fail then "bg-buildfail"
    when :fail       then "bg-danger"
    when :pending    then "bg-info"
    when :mixed      then "bg-warning"
    when :all_pass   then "bg-success"
    else "bg-skipped"
    end
  end

  # One-line mono summary text for a per-computer row. Worst-first
  # ranking matches the design's "right side of the sidebar entry":
  # "no build" → "{n} fail" → "{n} pending" → wrench + checksum
  # counts → "{pass} ok".
  def summary_for_computer(row)
    counts = row[:counts]
    return "no build" if row[:state] == :build_fail
    return "#{counts[:fail]} fail" if counts[:fail].positive?
    return "#{counts[:pending]} pending" if counts[:pending].positive?
    flag_parts = []
    flag_parts << "#{counts[:fpe]} fpe" if counts[:fpe].positive?
    flag_parts << "#{counts[:checksum]} ≠" if counts[:checksum].positive?
    return flag_parts.join(" · ") if flag_parts.any?
    "#{counts[:pass]} ok"
  end

  # Categories a single per_test_summary row belongs to. A row can
  # carry multiple — a passing-with-checksum-mismatch row appears
  # under both "checksums" and (depending on flags) maybe "fpe" —
  # so the Tests tab's filter chips work as a multi-tag system
  # rather than a strict partition.
  #
  # Categories:
  #   failing   — `:fail` (uniform failure across built computers)
  #   mixed     — `:mixed` (passes on some, fails on others)
  #   pending   — `:pending` (runs in progress)
  #   checksums — passing rows with a bit-for-bit divergence
  #               (`counts[:checksum] > 0`), after the existing
  #               run_optional / fine-resolution exclusions
  #   fpe       — passing rows with an FPE flag
  #   passing   — `:pass` (clean pass, no flags)
  #   untested  — `:not_run` (no built-computer ever reported)
  def test_row_categories(row)
    cats = case row[:overall]
           when :fail    then ["failing"]
           when :mixed   then ["mixed"]
           when :pending then ["pending"]
           when :pass    then ["passing"]
           when :not_run then ["untested"]
           else []
           end
    counts = row[:counts] || {}
    # `:flagged` plus the explicit checksum/fpe counts populate the
    # narrower category tags. Even a row classified as `:fail` /
    # `:mixed` can carry flag tags so the chips behave consistently
    # ("Checksums" includes every row with a checksum divergence,
    # regardless of overall state).
    cats << "checksums" if counts[:checksum].to_i.positive?
    cats << "fpe"       if counts[:fpe].to_i.positive?
    # Pending acts as a cross-cutting tag too — a row with one
    # failure plus several unreported computers belongs under
    # "Pending" as well as "Failing", so the chip surfaces
    # everything still in flight regardless of its dominant state.
    cats << "pending" if counts[:pending].to_i.positive? && row[:overall] != :pending
    cats.uniq
  end

  # Choose the most useful chip to land on by default when the user
  # opens the matrix. Worst-first priority — surface failures before
  # mixed, mixed before pending, etc. Falls back to "all" only when
  # the commit is entirely clean, since on a clean commit the wall
  # of green is the answer the user came for.
  def default_matrix_filter(per_test)
    return "all" if per_test.empty?
    counts = { fail: 0, mixed: 0, pending: 0, checksum: 0, fpe: 0 }
    per_test.each do |row|
      counts[:fail]    += 1 if row[:overall] == :fail
      counts[:mixed]   += 1 if row[:overall] == :mixed
      counts[:pending] += 1 if (row[:counts] || {})[:pending].to_i.positive? ||
                               row[:overall] == :pending
      counts[:checksum] += 1 if (row[:counts] || {})[:checksum].to_i.positive?
      counts[:fpe]     += 1 if (row[:counts] || {})[:fpe].to_i.positive?
    end
    return "failing"   if counts[:fail].positive?
    return "mixed"     if counts[:mixed].positive?
    return "pending"   if counts[:pending].positive?
    return "checksums" if counts[:checksum].positive?
    return "fpe"       if counts[:fpe].positive?
    "all"
  end

  # Compute per-category row counts for the Tests-tab filter
  # chips. The "all" bucket is the total row count; every other
  # bucket is the number of rows that contain that category tag.
  def tests_filter_counts(per_test)
    counts = Hash.new(0)
    counts["all"] = per_test.size
    per_test.each do |row|
      test_row_categories(row).each { |cat| counts[cat] += 1 }
    end
    counts
  end

  # Dot color for a per-test summary row. The design treats :flagged
  # the same as :mixed for the indicator color (a passing-but-flagged
  # test is amber, not green) — different from :pass.
  def status_dot_class_for_test(overall)
    case overall
    when :fail    then "bg-danger"
    when :mixed   then "bg-warning"
    when :flagged then "bg-warning"
    when :pending then "bg-info"
    when :pass    then "bg-success"
    else "bg-skipped"
    end
  end

  # Numeric badge for the Tests tab. Picks the first nonzero of
  # (uniform_failing, mixed, fpe+checksum) — matches the prototype's
  # priority. Returns `[value, tone_classes]` or nil when no badge
  # should render. Tone is the Tailwind class pair for the badge
  # background + text color.
  def tests_tab_badge(state)
    tests = state[:tests]
    flags = state[:flags]
    if tests[:uniform_failing_tests].positive?
      [tests[:uniform_failing_tests], "bg-danger-soft text-danger-soft-text"]
    elsif tests[:mixed_tests].positive?
      [tests[:mixed_tests], "bg-warning-soft text-warning-soft-text"]
    elsif (flags[:fpe].to_i + flags[:checksum].to_i).positive?
      [flags[:fpe].to_i + flags[:checksum].to_i, "bg-warning-soft text-warning-soft-text"]
    end
  end

  # Numeric badge for the Computers tab. Equal to the failed-build
  # count; toned buildfail when *every* build failed, otherwise amber.
  # Returns `[value, tone_classes]` or nil.
  def computers_tab_badge(state)
    failed = state[:build][:failed_build_computer_ids].size
    return nil if failed.zero?
    tone =
      if state[:build][:status] == :all_fail
        "bg-buildfail-soft text-buildfail-soft-text"
      else
        "bg-warning-soft text-warning-soft-text"
      end
    [failed, tone]
  end

  # SDK/compiler chip text for a per-computer card. Returns the
  # unique non-blank `computer_specification` strings across this
  # computer's submissions for the commit. Joined with a thin slash
  # so a single submission renders as one chip and a SDK-vs-compiler
  # split surfaces as "SDK 24.3.1 mkl / gfortran 13.2".
  def computer_sdk_label(row)
    subs = row[:submissions] || []
    specs = subs.map { |s| s.computer_specification.to_s }.map(&:strip)
                .reject(&:blank?).uniq
    return nil if specs.empty?
    specs.join(" / ")
  end

  # CSS color token name (sans `--color-` prefix) keyed to a per-row
  # state symbol. Used by the Computers tab's card-border accent.
  def computer_state_color(state)
    {
      build_fail: "buildfail",
      fail: "danger",
      pending: "info",
      mixed: "warning",
      all_pass: "success"
    }.fetch(state, "skipped")
  end

  # Compact one-line summary for a per-test row in the Tests tab.
  def summary_for_test(row)
    return "not run" if row[:overall] == :not_run
    counts = row[:counts]
    return "#{counts[:fail]} fail" if counts[:fail] > 0 && counts[:pass] == 0
    return "#{counts[:fail]} fail · #{counts[:pass]} pass" if counts[:fail].positive?
    return "#{counts[:pending]} pending" if counts[:pending].positive?
    flag_parts = []
    flag_parts << "#{counts[:fpe]} fpe" if counts[:fpe].positive?
    flag_parts << "#{counts[:checksum]} ≠" if counts[:checksum].positive?
    return flag_parts.join(" · ") if flag_parts.any?
    "#{counts[:pass]} ok"
  end

  # Synthetic before/after cells for the Diff tab. The before cell is
  # always a clean pass (since `cells_changed_since` filters to rows
  # whose prior state was a passing cell). The after cell mirrors the
  # actual change so the visual matches the matrix cell encoding used
  # everywhere else in the page.
  def diff_before_cell
    { status: :pass, flags: { fpe: false, checksum: false, inlists_full: false } }
  end

  def diff_after_cell(row)
    base = { fpe: false, checksum: false, inlists_full: false }
    case row[:change]
    when :new_failure
      { status: :fail, flags: base }
    when :new_flag
      flags = base.merge(row[:flag_kind] => true)
      { status: :pass, flags: flags }
    else
      { status: :pass, flags: base }
    end
  end

  # Short text label for an after-cell's status change. Mirrors the
  # cell encoding so the row reads even without the visual (e.g. when
  # the cell drawings get clipped on narrow viewports).
  def diff_change_label(row)
    case row[:change]
    when :new_failure then "now failing"
    when :new_flag
      row[:flag_kind] == :fpe ? "FPE raised" : "checksum ≠"
    else "changed"
    end
  end

  # Grouped count line for the diff tab header. Returns a short
  # human-readable summary of what kinds of changes the diff contains
  # (e.g. "3 new failures · 1 new FPE flag"). Empty rows return nil.
  def diff_summary_line(rows)
    return nil if rows.blank?
    failures = rows.count { |r| r[:change] == :new_failure }
    fpe      = rows.count { |r| r[:change] == :new_flag && r[:flag_kind] == :fpe }
    checks   = rows.count { |r| r[:change] == :new_flag && r[:flag_kind] == :checksum }

    parts = []
    parts << pluralize(failures, "new failure") if failures.positive?
    parts << pluralize(fpe, "new FPE flag") if fpe.positive?
    parts << "#{checks} new checksum #{checks == 1 ? 'mismatch' : 'mismatches'}" if checks.positive?
    parts.join(" · ").presence
  end

  # Initials avatar for a commit author. Hue is deterministically
  # derived from the name so the same author looks the same across
  # pages. Soft hue, dark text, 22px circle.
  def commit_avatar(author, size: 22)
    initials = author.to_s.split(/\s+/).first(2).map { |n| n[0]&.upcase }.compact.join.presence || "?"
    hue = author.to_s.bytes.sum % 360
    content_tag(:span,
                initials,
                style: "background: hsl(#{hue}, 60%, 90%); color: hsl(#{hue}, 50%, 25%); width: #{size}px; height: #{size}px; line-height: #{size}px;",
                class: "inline-block rounded-full text-center text-[10px] font-semibold")
  end

  # Age bucket for a commit's commit_time, relative to a reference
  # `now` (typically the active date-picker cursor, not real-world
  # today). Labels are deliberately cursor-relative ("Same day" /
  # "Day before") so they don't read as today-relative when the user
  # is browsing the distant past — "Last week" would otherwise sound
  # like real-world last week even with the cursor pinned at 2024.
  AGE_BUCKETS = [
    [:today, "Same day"],
    [:yesterday, "Day before"],
    [:this_week, "Earlier same week"],
    [:last_week, "Week before"],
    [:this_month, "Earlier same month"],
    [:older, "Older"]
  ].freeze

  def age_bucket(time, now: Time.current)
    t = time.in_time_zone(now.time_zone)
    today = now.beginning_of_day
    t_day = t.beginning_of_day
    day_diff = ((today.to_date - t_day.to_date).to_i)
    return :today if day_diff <= 0
    return :yesterday if day_diff == 1
    start_of_this_week = today.beginning_of_week(:monday)
    start_of_last_week = start_of_this_week - 7.days
    return :this_week if t_day >= start_of_this_week
    return :last_week if t_day >= start_of_last_week
    return :this_month if t.year == now.year && t.month == now.month
    :older
  end

  # Group an enumerable of commits into ordered age buckets. Empty
  # buckets are dropped.
  def group_commits_by_age(commits, now: Time.current)
    by_bucket = AGE_BUCKETS.to_h { |id, _| [id, []] }
    commits.each { |c| by_bucket[age_bucket(c.commit_time, now: now)] << c }
    AGE_BUCKETS.filter_map do |id, label|
      next nil if by_bucket[id].empty?
      [id, label, by_bucket[id]]
    end
  end

  # Past-tense "6d ago" / "2w ago" / "3mo ago" — the conventional shape
  # for "how long ago was this committed?" Used on the commit detail
  # hero where there's no cursor to anchor a "−6d" reading to.
  def time_ago_compact(time)
    seconds = (Time.current - time).to_i
    return "just now" if seconds < 60
    return "#{seconds / 60}m ago"   if seconds < 3600
    return "#{seconds / 3600}h ago" if seconds < 86_400
    return "#{seconds / 86_400}d ago" if seconds < 86_400 * 30
    return "#{seconds / (86_400 * 30)}mo ago" if seconds < 86_400 * 365
    "#{seconds / (86_400 * 365)}y ago"
  end

  # Compact "−6d" / "−2w" / "−3mo" offset from a reference moment.
  # Reads as "six days before the cursor" regardless of where the
  # cursor sits in time, which avoids the "Xd ago" → "ago from
  # today??" confusion when browsing older dates.
  def short_relative_time(time, now: Time.current)
    seconds = (now - time).to_i
    return "now" if seconds.abs < 60
    sign = seconds.negative? ? "+" : "−"
    s = seconds.abs
    return "#{sign}#{s / 60}m" if s < 3600
    return "#{sign}#{s / 3600}h" if s < 86_400
    return "#{sign}#{s / 86_400}d" if s < 86_400 * 30
    return "#{sign}#{s / (86_400 * 30)}mo" if s < 86_400 * 365
    "#{sign}#{s / (86_400 * 365)}y"
  end

  private

  def pill_classes(size)
    base = "inline-flex items-center gap-1 rounded-full border border-transparent font-medium align-middle"
    case size
    when :sm
      "#{base} px-1.5 py-0.5 text-[10px]"
    else
      "#{base} px-2 py-0.5 text-[11px]"
    end
  end
end
