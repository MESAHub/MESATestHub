# View helpers used by the daily mailer template and its in-app preview.
# Everything here returns email-safe inline style strings or short HTML
# fragments — no Tailwind utility classes, since most email clients
# don't load the Tailwind build.
module MorningMailerHelper
  # Badge palettes: (dark-mode css class, always-on light-mode style).
  # The class is referenced by the mailer layout's dark-mode @media
  # rules.
  BADGE_TONES = {
    success:  ['mesa-badge-success',  'background:#d8f5df; color:#0a5825;'],
    danger:   ['mesa-badge-danger',    'background:#ffe4e6; color:#a40e26;'],
    mixed:    ['mesa-badge-mixed',     'background:#fef6cf; color:#6b4900;'],
    fpe:      ['mesa-badge-fpe',       'background:#fde4f2; color:#9d1c6c;'],
    checksum: ['mesa-badge-checksum',  'background:#ede5ff; color:#5b21b6;'],
    info:     ['mesa-badge-info',      'background:#e3e8ff; color:#2a3fd1;'],
    muted:    ['mesa-badge-skipped',   'background:#eceef2; color:#57606a;']
  }.freeze

  def mailer_badge(text, tone, title: nil)
    klass, style = BADGE_TONES.fetch(tone)
    badge_pill(text: text, klass: klass, style: style, title: title)
  end

  # The tests pill, worded like the site's `test_status_pill` so the
  # email and the commit pages agree.
  def mailer_tests_pill(summary)
    t = summary.tests
    case summary.tests_status
    when :fail then mailer_badge("#{t[:uniform_failing_tests]} failing", :danger)
    when :mixed then mailer_badge("#{t[:mixed_tests]} mixed", :mixed)
    when :fpe then mailer_badge("#{t[:fpe_tests]} FPE", :fpe)
    when :checksum then mailer_badge("#{t[:checksum_tests]} checksum ≠", :checksum)
    when :pending, :pending_partial then mailer_badge('Pending', :info)
    when :partial then mailer_badge("#{t[:reported_tests]}/#{t[:total_tests]} passing", :muted)
    when :all_pass then mailer_badge('All passing', :success)
    else mailer_badge('Untested', :muted)
    end
  end

  # Only failed builds get a badge; a good build is the norm and
  # labeling every row "Build: OK" buried the ones that weren't.
  def mailer_build_badge(summary)
    case summary.build_status
    when :all_fail
      mailer_badge('Build failed', :danger)
    when :some_fail
      names = summary.failed_build_computers
      text = names.size == 1 ? "Build failed on #{names.first}" : "Build failed on #{names.size}"
      mailer_badge(text, :danger, title: names.join(', '))
    else
      ''.html_safe
    end
  end

  # One line under a commit: how many tests have results, on how many
  # computers, and how many are still claimed.
  def mailer_coverage_text(summary)
    t = summary.tests
    parts = []
    if t[:total_tests].to_i.positive?
      parts << "#{t[:reported_tests]}/#{t[:total_tests]} tests reported"
    end
    parts << pluralize(summary.computer_count, 'computer') if summary.computer_count.positive?
    parts << "#{t[:pending_tests]} pending" if t[:pending_tests].to_i.positive?
    parts.join(' · ')
  end

  # Short-form badges for the inline per-test-case-commit lists.
  TCC_BADGES = {
    failing: ['Fail', :danger],
    mixed: ['Mixed', :mixed],
    fpe: ['FPE', :fpe],
    checksums: ['Checksum ≠', :checksum]
  }.freeze

  def mailer_tcc_badge(label)
    text, tone = TCC_BADGES.fetch(label, TCC_BADGES[:failing])
    mailer_badge(text, tone)
  end

  def badge_pill(text:, klass:, style:, title: nil)
    content_tag(:span, text,
                class: klass, title: title,
                style: "display:inline-block; padding:2px 8px; " \
                       "border-radius:999px; font-size:11px; " \
                       "font-weight:600; line-height:1.5; white-space:nowrap; #{style}")
  end

  # 7-char SHA in a pill for the per-commit header.
  def mailer_sha_pill(commit)
    content_tag(:code, commit.short_sha,
                style: 'display:inline-block; padding:1px 6px; ' \
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

  # Commit detail URL, or nil when the commit is on no branch (it has
  # no page to link to).
  def mailer_commit_url(summary)
    return nil unless summary.link_branch_name

    commit_url(branch: summary.link_branch_name, sha: summary.commit.short_sha)
  end

  # Test-case-commit detail URL, or nil when the commit is on no branch.
  def mailer_test_case_commit_url(summary, tcc)
    return nil unless summary.link_branch_name

    test_case_commit_url(branch: summary.link_branch_name,
                         module: tcc.test_case.module,
                         test_case: tcc.test_case.name,
                         sha: summary.commit.short_sha)
  end

  # link_to when there's a URL, plain span otherwise.
  def mailer_link_or_text(text, url, style:)
    if url
      link_to text, url, class: 'mesa-link mesa-fg', style: style
    else
      content_tag(:span, text, class: 'mesa-fg', style: style)
    end
  end

  # Branch names for a family section's sub-heading, capped.
  def mailer_branch_list(names, max: 8)
    shown = names.first(max).join(' · ')
    names.size > max ? "#{shown} · and #{names.size - max} more" : shown
  end

  # An anomaly's value or cohort mean, with units. Runtime is stored in
  # minutes, memory in kB.
  def mailer_anomaly_value(anomaly, value)
    if anomaly.memory?
      gb = value.to_f / (1024.0 * 1024.0)
      format(gb >= 10 ? '%.1f GB' : '%.2f GB', gb)
    else
      mailer_runtime_display(value.to_f * 60)
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
  # test case and computer, passing runs over the last six months — so
  # the reader can see the history the comparison came from.
  def mailer_anomaly_cohort_url(anomaly)
    ti = anomaly.test_instance
    from = (ti.created_at - 6.months).to_date
    to   = ti.created_at.to_date
    pieces = [
      "test_case: #{ti.test_case.name}",
      "computer: #{ti.computer.name}",
      "passed: true",
      "commit_datetime: #{from}-#{to}"
    ]
    search_instances_url(query_text: pieces.join('; '))
  end
end
