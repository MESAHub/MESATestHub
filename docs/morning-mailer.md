# Daily digest mailer

Sends a daily summary email to mesa-developers and the #testhub
Slack inbound-mail address.  Mirrors the historical "morning mail"
that the Heroku app ran, ported onto the commits-based data model
that replaced the SVN-era `Version` rows.

## Pieces

- **[`app/services/morning_report.rb`](../app/services/morning_report.rb)**
  PORO that builds the report data.  Computes a 24-hour window
  ending at `as_of` (defaults to `Date.current.end_of_day`), groups
  commits-tested-in-window by branch (main first), pulls per-commit
  pass/fail/checksum/mixed scalars, and flags individual passing
  test instances whose runtime or RAM is far above the recent
  cohort of `(test_case, computer, run_optional, fpe_checks)`
  matches.  Result is cached in `Rails.cache` for 24 hours per
  `date.iso8601` key.
- **[`app/mailers/morning_mailer.rb`](../app/mailers/morning_mailer.rb)**
  Single `#daily` action that builds the report and renders the
  email.  Hardcoded recipients in `MorningMailer::RECIPIENTS`
  (mesa-developers list + the #testhub Slack inbound-mail address).
- **[`app/views/morning_mailer/daily.html.haml`](../app/views/morning_mailer/daily.html.haml)**
  + **[`app/views/layouts/morning_mailer.html.haml`](../app/views/layouts/morning_mailer.html.haml)**
  Email-safe HTML — inline styles for everything load-bearing, a
  `<style>` block layered on top for `:hover` and a
  `prefers-color-scheme: dark` media query that flips colors for
  iOS / Apple Mail / Outlook.com dark-mode users.  Tables for
  layout (Outlook compatibility), 600 px max width.
- **[`app/controllers/morning_report_controller.rb`](../app/controllers/morning_report_controller.rb)**
  In-browser preview at `/morning_report`.  Renders the same
  template inside the modern app layout so the user can navigate
  away.  Accepts `?date=YYYY-MM-DD` for historical previews and
  `?refresh=1` to bust the 24-hour cache.
- **[`lib/tasks/morning_mailer.rake`](../lib/tasks/morning_mailer.rake)**
  `morning_mailer:daily` rake task — what cron invokes.

## Anomaly detection

For each passing test instance in the window, compares its runtime
and RAM metrics against a cohort of recent passing runs matching:

- same `test_case_id`
- same `computer_id`
- same `run_optional` (full vs partial)
- same `fpe_checks` (whether FPE checks were enabled)

The cohort is the **previous `COHORT_LIMIT` = 50** passing
instances strictly before the candidate's commit time.  An
anomaly is flagged when *both*:

- z-score above the cohort mean ≥ `ANOMALY_Z_THRESHOLD = 3.0`,
  **and**
- ratio of value to cohort mean ≥ `ANOMALY_RATIO_FLOOR = 1.25`
  (protects against tiny-variance cohorts where 3σ is a
  meaningless absolute jump).

Cohorts smaller than `COHORT_MIN_SIZE = 8` are skipped.

Metrics checked: `runtime_seconds` (rn), `re_time` (re),
`total_runtime_seconds` (whole test), `mem_rn`, `mem_re`.

Tweak the thresholds in `MorningReport` if the signal-to-noise is
off for your use case.

## Scheduling — 8 AM US Eastern

The intended cadence is **8:00 AM US Eastern Time** every day.
Daylight Saving makes that a moving UTC target, so configure cron
with the `TZ` env var rather than encoding the offset:

### Railway

In the Railway service settings → **Cron Triggers**:

```
Command:  bundle exec rake morning_mailer:daily
Schedule: 0 8 * * *
TZ env:   America/New_York
```

(Set `TZ=America/New_York` on the same service or directly on the
cron config.  Railway evaluates the schedule against `TZ` when
present, so 8 AM Eastern stays 8 AM Eastern across DST.)

### Local manual send

```
DISABLE_SPRING=1 bundle exec rake morning_mailer:daily
```

## Preview & cache

- **Web preview**: `/morning_report` (or
  `/morning_report?date=YYYY-MM-DD` for a historical run).
- **Cache key**: `morning_report:<date.iso8601>`, 24-hour TTL.
- **Force rebuild**: `?refresh=1` query param, or
  `MorningReport.for(date: ..., force: true)`.
- **Test environment**: cache backend is `:null_store` (see
  `config/environments/test.rb`), so spec runs always build a
  fresh report.
