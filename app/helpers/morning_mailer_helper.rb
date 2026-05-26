# View helpers used by the daily mailer template and its in-app preview.
# Everything here returns email-safe inline style strings or short HTML
# fragments — no Tailwind utility classes, since most email clients
# don't load the Tailwind build.
module MorningMailerHelper
  # Map MorningReport::CommitSummary#status_label to a (label, badge css
  # class, inline style) tuple. The CSS class is referenced by the
  # mailer layout's dark-mode @media rules; the inline style is the
  # always-on light-mode look.
  STATUS_STYLES = {
    passing:   { label: 'Passing',   klass: 'mesa-badge-success',
                 style: 'background:#d8f5df; color:#0a5825;' },
    failing:   { label: 'Failing',   klass: 'mesa-badge-danger',
                 style: 'background:#ffe4e6; color:#a40e26;' },
    checksums: { label: 'Checksums', klass: 'mesa-badge-warning',
                 style: 'background:#fef6cf; color:#6b4900;' },
    mixed:     { label: 'Mixed',     klass: 'mesa-badge-mixed',
                 style: 'background:#fef6cf; color:#6b4900;' },
    # `:untested` is `Commit#status = -1` — the rollup hasn't
    # finalized (CI run in progress, or no rollup row yet). Renders
    # in neutral gray so it doesn't masquerade as Passing.
    untested:  { label: 'Untested',  klass: 'mesa-badge-skipped',
                 style: 'background:#eceef2; color:#57606a;' }
  }.freeze

  # Falls back to the untested style for any unexpected label rather
  # than silently labeling unknowns as Passing — the previous behavior
  # masked status=-1 commits as green.
  def mailer_status_badge(label)
    style = STATUS_STYLES[label] || STATUS_STYLES[:untested]
    badge_pill(text: style[:label], klass: style[:klass], style: style[:style])
  end

  def mailer_anomaly_badge
    badge_pill(text: 'Anomaly',
               klass: 'mesa-badge-danger',
               style: 'background:#ffe4e6; color:#a40e26;')
  end

  def badge_pill(text:, klass:, style:)
    content_tag(:span, text,
                class: klass,
                style: "display:inline-block; padding:2px 8px; " \
                       "border-radius:999px; font-size:11px; " \
                       "font-weight:600; line-height:1.5; #{style}")
  end

  # 8-char SHA in a pill for the per-commit header.
  def mailer_sha_pill(commit)
    content_tag(:code, commit.short_sha,
                style: 'display:inline-block; padding:2px 8px; ' \
                       'border-radius:6px; background:#eceef2; ' \
                       'color:#1f2328; font-family:ui-monospace, ' \
                       'SFMono-Regular,Menlo,monospace; font-size:12px; ' \
                       'font-weight:600;')
  end

  # Short summary line for the commit card: first line of the message.
  def mailer_message_excerpt(commit, length: 90)
    msg = commit.message.to_s.split("\n").first.to_s.strip
    msg.length > length ? "#{msg[0, length - 1]}…" : msg
  end

  # Memory in raw bytes (×1024² of GB on disk) → display GB string.
  def mailer_memory_display(value_in_kb_squared)
    return '0' if value_in_kb_squared.to_i.zero?

    gb = value_in_kb_squared.to_f / (1024.0 * 1024.0)
    if gb >= 10
      format('%.1f', gb)
    else
      format('%.2f', gb)
    end
  end

  # Time in seconds → display string. Seconds for short runs, minutes
  # for longer, hours for very long.
  def mailer_runtime_display(seconds)
    seconds = seconds.to_i
    return "#{seconds}s" if seconds < 90

    minutes = seconds / 60.0
    return format('%.1f min', minutes) if minutes < 60

    format('%.1f hr', minutes / 60.0)
  end

  # Search-page URL pointing at the cohort behind an anomaly — same
  # (test_case, computer, run_optional/fpe context) and a commit-time
  # window that maps to the cohort lookback. The user lands on a fully
  # populated query so they can see the historical data for themselves.
  # Test-case-commit detail URL — wraps the four-keyword route helper so
  # the HAML template can use it on one line.
  def mailer_test_case_commit_url(branch_name, tcc, commit)
    test_case_commit_url(branch: branch_name,
                         module: tcc.test_case.module,
                         test_case: tcc.test_case.name,
                         sha: commit.short_sha)
  end

  def mailer_anomaly_cohort_url(anomaly)
    ti = anomaly.test_instance
    from = (ti.commit.commit_time - 6.months).to_date
    to   = ti.commit.commit_time.to_date
    pieces = [
      "test_case: #{ti.test_case.name}",
      "computer: #{ti.computer.name}",
      "passed: true",
      "commit_datetime: #{from}-#{to}"
    ]
    search_instances_url(query_text: pieces.join('; '))
  end
end
