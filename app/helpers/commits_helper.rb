module CommitsHelper
  # Inline SVG icons matching the design's stroke-only set (16x16,
  # stroke-width 1.5, currentColor). Tailwind's `text-*` utilities
  # color these.
  ICON_PATHS = {
    check: '<path d="M3 8.5l3.5 3.5L13 5.5"/>'.html_safe,
    x: '<path d="M4 4l8 8M12 4l-8 8"/>'.html_safe,
    branch: '<circle cx="5" cy="3" r="1.5"/><circle cx="5" cy="13" r="1.5"/><circle cx="11" cy="8" r="1.5"/><path d="M5 4.5v7M5 9c0-2 3-2 3-3.5"/>'.html_safe,
    chevron: '<path d="M4 6l4 4 4-4"/>'.html_safe,
    search: '<circle cx="7" cy="7" r="4"/><path d="M10 10l3 3"/>'.html_safe,
    clock: '<circle cx="8" cy="8" r="6"/><path d="M8 4.5V8l2.5 1.5"/>'.html_safe,
    eye_off: '<path d="M2 8s2-4 6-4 6 4 6 4-2 4-6 4-6-4-6-4zM2 2l12 12"/>'.html_safe,
    warn: '<path d="M8 2l6 11H2l6-11zM8 7v3M8 11.5v.01"/>'.html_safe,
    wrench: '<path d="M10.5 1.5a3 3 0 014 4l-1.5 1.5-1-1 1.2-1.2a1.5 1.5 0 00-2.1-2.1L10 3.8l-1-1 1.5-1.3zM9 5l5 5-3 3-5-5 3-3zM5.5 8.5l-3 3a1 1 0 001.4 1.4l3-3"/>'.html_safe,
    neq: '<path d="M3 6h10M3 10h10"/><path d="M11 3l-6 10"/>'.html_safe,
    plus: '<path d="M8 3v10M3 8h10"/>'.html_safe
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
  # Incomplete / Untested.
  #
  # Mapping note: `:pending` (TCCs exist, no submissions) and
  # `:not_run` (no test data at all) both render as gray "Untested"
  # since the codebase doesn't model a "promised but not yet
  # submitted" distinction. Blue is reserved for `:pending_partial`
  # — some test cases have passing submissions, others are still
  # waiting — which is genuinely actionable ("a run is mid-flight").
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
        safe_join([mesa_icon(:clock, size: 11), "Incomplete"], " ")
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
