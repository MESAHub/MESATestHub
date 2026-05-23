module TestCaseCommitsHelper
  # Column catalog for the test-on-commit instances table. Mirrors the
  # design handoff's column model (see prototype/screens.jsx
  # `COLUMN_DEFS`) grouped into Run / Output / Convergence. Each entry:
  #
  #   id:      stable string used in URLs, CSS, and localStorage
  #   group:   "Run" | "Output" | "Convergence"
  #   label:   header label
  #   default: shown when no localStorage preference is set
  #   align:   "left" | "right" — text alignment in cells
  #   width:   min-width in px (just the content; the controller's
  #            `whitespace-nowrap` keeps the header on one line)
  #   mono:    render in JetBrains Mono
  #
  # The view always renders every column; visibility is a pure
  # client-side toggle driven by `column_picker_controller.js`.
  #
  # We dropped the prototype's `variant` column — its values
  # (default / photo / full / fpe / fine) are already encoded in
  # the status-cell icons (wrench / ≠ / + / ...) and the success_type
  # half of the status label ("PASS: Photo Checksum"), so the column
  # was pure visual duplication that pushed the default set past a
  # one-screen-wide layout.
  INSTANCE_COLUMNS = [
    { id: "computer",          group: "Run",         label: "Computer",     default: true,  align: "left",  width: 100, mono: true  },
    { id: "date",              group: "Run",         label: "Date",         default: false, align: "left",  width: 130, mono: false },
    { id: "threads",           group: "Run",         label: "Threads",      default: false, align: "right", width: 70,  mono: false },
    { id: "spec",              group: "Run",         label: "Spec",         default: false, align: "left",  width: 130, mono: true  },
    { id: "runtime",           group: "Run",         label: "Runtime",      default: true,  align: "right", width: 80,  mono: false },
    { id: "ram",               group: "Run",         label: "RAM",          default: false, align: "right", width: 80,  mono: false },
    { id: "checksum",          group: "Output",      label: "Checksum",     default: true,  align: "left",  width: 90,  mono: true  },
    { id: "model_number",      group: "Output",      label: "Model №",      default: false, align: "right", width: 90,  mono: false },
    { id: "steps",             group: "Output",      label: "Steps",        default: true,  align: "right", width: 70,  mono: false },
    { id: "star_age",          group: "Output",      label: "Star Age",     default: true,  align: "right", width: 100, mono: false },
    { id: "cum_retries",       group: "Convergence", label: "Cum. Retries", default: true,  align: "right", width: 100, mono: false },
    { id: "retries",           group: "Convergence", label: "Retries",      default: false, align: "right", width: 80,  mono: false },
    { id: "redos",             group: "Convergence", label: "Redos",        default: false, align: "right", width: 70,  mono: false },
    { id: "solver_iters",      group: "Convergence", label: "Solver Iters", default: false, align: "right", width: 100, mono: false },
    { id: "solver_calls",      group: "Convergence", label: "Solver Calls", default: false, align: "right", width: 100, mono: false },
    { id: "solver_calls_failed", group: "Convergence", label: "Calls Failed", default: true,  align: "right", width: 100, mono: false },
    { id: "log_rel_e",         group: "Convergence", label: "log Rel E",    default: false, align: "right", width: 90,  mono: false },
    { id: "num_retries",       group: "Convergence", label: "Num Retries",  default: false, align: "right", width: 100, mono: false },
    { id: "inlist_retries",    group: "Convergence", label: "Inlist Retries", default: true,  align: "right", width: 110, mono: false }
  ].freeze

  INSTANCE_COLUMN_GROUPS = INSTANCE_COLUMNS.map { |c| c[:group] }.uniq.freeze

  INSTANCE_COLUMN_PRESETS = {
    "default"     => INSTANCE_COLUMNS.select { |c| c[:default] }.map { |c| c[:id] },
    "performance" => %w[computer threads spec runtime ram steps checksum],
    "convergence" => %w[computer checksum cum_retries retries redos solver_calls solver_calls_failed num_retries inlist_retries],
    "all"         => INSTANCE_COLUMNS.map { |c| c[:id] }
  }.freeze

  # Last inlist (in run order) for a row hash from
  # `TestCaseCommit#instances_for_display`. Per-inlist metrics
  # (model_number, star_age, retries, num_retries) come from the
  # final inlist run for the instance, mirroring the existing
  # Bootstrap view's "show last inlist's numbers" semantics.
  def last_inlist(row)
    inlists = row[:inlists] || []
    return nil if inlists.empty?
    inlists.max_by { |i| i[:order].to_i }
  end

  # Format a cell value for display. Handles nil/empty as an em-dash so
  # the table is calm when data is missing, applies the column's
  # alignment + mono treatment, and formats numerics consistently.
  def format_instance_cell(value, column)
    return content_tag(:span, "—", class: "text-fg-subtle") if value.nil? || value.to_s.strip.empty?
    text =
      case column[:id]
      when "runtime"  then format("%.2f m", value.to_f)
      when "ram"      then format("%.0f MB", value.to_f / 1024.0)
      when "log_rel_e" then format("%.2f", value.to_f)
      when "star_age" then format("%.3e", value.to_f)
      when "checksum" then value.to_s
      when "date"     then format_time(value)
      else value.to_s
      end
    text
  end

  # Worst-first status word + color token for the headline sentence.
  # Returns `[word, css_class]` for "is `<word>`" in the headline.
  def headline_status(test_case_commit)
    statuses = test_case_commit.test_instances.map { |ti| ti.passed ? :pass : :fail }.uniq
    if statuses.include?(:fail) && statuses.include?(:pass)
      ["mixed", "text-warning-soft-text"]
    elsif statuses.include?(:fail)
      ["failing", "text-danger-soft-text"]
    elsif statuses.empty?
      ["untested", "text-fg-muted"]
    else
      ["passing", "text-success-soft-text"]
    end
  end

  # Checksum count word + color token for the "with X unique
  # checksum(s)" tail of the headline sentence.
  def headline_checksum(test_case_commit)
    n = test_case_commit.checksum_count.to_i
    word =
      case n
      when 0 then "no"
      when 1 then "one"
      when 2 then "two"
      when 3 then "three"
      else n.to_s
      end
    color =
      case n
      when 0 then "text-fg-muted"
      when 1 then "text-success-soft-text"
      else "text-warning-soft-text"
      end
    [word, color, n]
  end

  # Status-dot Tailwind background class for a single instance row.
  def instance_dot_class(row)
    case row[:status]
    when :pass then "bg-success"
    when :fail then "bg-danger"
    when :pending then "bg-info"
    else "bg-skipped"
    end
  end

  # Categories used by the segmented status filter. Each row carries
  # one — the controller hides rows whose status doesn't match the
  # active value.
  def instance_status_tag(row)
    case row[:status]
    when :pass then "pass"
    when :fail then "fail"
    when :pending then "pending"
    else "other"
    end
  end

  # Sort rank for the in-commit test picker dropdown. Matches the
  # worst-first ordering used everywhere else in the modern UI:
  # failing → mixed → checksum-only → passing → untested. Values are
  # the `TestCaseCommit#status` integers (see TestCaseCommit's
  # @@status_encoder):
  #
  #   1 → failing
  #   3 → mixed (pass and fail on the same commit)
  #   2 → mixed_checksums (passed but bit-for-bit divergence)
  #   0 → passing
  #  -1 → untested
  #
  # Anything else (corrupted row) lands at the bottom.
  def tcc_status_rank(status)
    { 1 => 0, 3 => 1, 2 => 2, 0 => 3, -1 => 4 }.fetch(status, 5)
  end

  # Sort an enumerable of TestCaseCommit by status (worst-first) →
  # module (reverse-alphabetical: star → binary → astero, exploiting
  # `TestCase.modules`' deliberate ordering) → test name
  # (alphabetical). Used to build the in-commit picker dropdown so
  # the user lands on the most-broken row first.
  def sorted_commit_tccs(tccs)
    module_order = ::TestCase.modules
    tccs.sort_by do |tcc|
      mod = tcc.test_case&.module.to_s
      [
        tcc_status_rank(tcc.status),
        module_order.index(mod) || module_order.size,
        tcc.test_case&.name.to_s
      ]
    end
  end

  # Tailwind background class for a per-TCC status dot — used by the
  # in-commit test picker and the test-history subway map. Worst-first
  # color vocabulary matches the rest of the modern UI: red = fail,
  # amber = mixed or checksum-only, green = pass, gray = untested.
  def tcc_status_dot_class(status)
    case status
    when 1 then "bg-danger"
    when 3 then "bg-warning"
    when 2 then "bg-warning"
    when 0 then "bg-success"
    when -1 then "bg-skipped"
    else "bg-skipped"
    end
  end

  # CSS color *token* (sans `--color-` prefix) for the subway map's
  # SVG circles — these don't accept Tailwind utility classes so we
  # feed them as `var(--color-<token>)` from the partial.
  def tcc_status_token(status)
    case status
    when 1 then "danger"
    when 3 then "warning"
    when 2 then "warning"
    when 0 then "success"
    when -1 then "skipped"
    else "skipped"
    end
  end

  # Short human-readable label for a TCC status integer — used as the
  # accessible-name suffix on the test picker rows and the subway
  # map stations.
  def tcc_status_word(status)
    case status
    when 1 then "failing"
    when 3 then "mixed"
    when 2 then "checksum mismatch"
    when 0 then "passing"
    when -1 then "untested"
    else "unknown"
    end
  end

  # Passage-status label for the table's status column. Mirrors the
  # legacy view's compact ALL-CAPS phrasing but uses the success/failure
  # types stored on the instance so passing instances surface their
  # success_type ("Photo Checksum", etc.) and failing instances surface
  # the failure mode.
  def instance_status_label(test_instance)
    if test_instance.passed
      base = "PASS"
      suffix = test_instance.success_type.to_s.strip
      suffix.empty? ? base : "#{base}: #{suffix.humanize}"
    else
      base = "FAIL"
      suffix = test_instance.failure_type.to_s.strip
      suffix.empty? ? base : "#{base}: #{suffix.humanize}"
    end
  end
end
