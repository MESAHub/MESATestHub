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

## Email provider — Resend

SMTP wiring in [`app/mailers/application_mailer.rb`](../app/mailers/application_mailer.rb)
is provider-agnostic: it defaults to Resend's SMTP endpoint
(`smtp.resend.com:465`, implicit TLS, username `resend`) but every
value is overridable via env vars.  Swapping to a different
provider is a config change, not a code change.

### Required env vars (cron service)

| Var | Default | Purpose |
|---|---|---|
| `SMTP_PASSWORD` *or* `RESEND_API_KEY` | — | API key from Resend's dashboard. The code reads `SMTP_PASSWORD` first, then falls back to `RESEND_API_KEY`, so either name works. |
| `SMTP_HOST` | `smtp.resend.com` | SMTP endpoint hostname. |
| `SMTP_PORT` | `465` | Use 465 for implicit TLS (matches the `tls: true` setting), or override to 587/2587 for STARTTLS (would also need a code tweak to swap `tls:` for `enable_starttls_auto:`). |
| `SMTP_USER` | `resend` | Resend uses the literal username `resend` for every account; only the password (API key) identifies you. |
| `DATABASE_URL` | — | Reference the Railway Postgres service: `${{Postgres.DATABASE_URL}}`. |
| `SECRET_KEY_BASE` | — | Required for Rails to boot. Reference the web service's: `${{MESATestHub.SECRET_KEY_BASE}}`. |
| `GIT_TOKEN` | — | Optional but recommended — without it, the digest shows "couldn't check" for the release-blocker line. Reference the web service's: `${{MESATestHub.GIT_TOKEN}}`. |
| `RAILS_ENV` | — | Set to `production`. |
| `TZ` | UTC | Set to `America/New_York` so the cron schedule evaluates in Eastern Time (DST-safe). |

### Domain verification in Resend

Resend requires the From-address's domain to be verified before it'll
relay mail.  We send from `digest@testhub.mesastar.org`, so:

1. **Resend dashboard** → Domains → Add Domain → `testhub.mesastar.org`.
2. Resend hands you three DNS records (SPF / DKIM / DMARC) to add at
   your DNS host.  These are TXT records on `testhub.mesastar.org`
   itself plus its `resend._domainkey.` subdomain — they don't
   conflict with the existing A record pointing at the app host.
3. Add the records, click **Verify** in Resend.  Propagation is
   usually under 5 minutes.

The visible From in subscribers' inboxes will be
`digest@testhub.mesastar.org`; the `mesa-developers@lists.mesastar.org`
list address stays in the To header so threading / archival behavior
is unchanged.

## Scheduling — 8 AM US Eastern

The intended cadence is **8:00 AM US Eastern Time** every day.
Daylight Saving makes that a moving UTC target, so configure cron
with the `TZ` env var rather than encoding the offset.

### Railway cron trigger

On the cron service:

1. **Variables** → set everything in the table above.
2. **Settings** → **Cron Schedule** → fill in:
   ```
   Cron Schedule:  0 8 * * *
   Cron Command:   bundle exec rake morning_mailer:daily
   ```
3. Combined with `TZ=America/New_York` from the variables, Railway
   evaluates `0 8 * * *` as 8 AM Eastern and the schedule tracks
   DST automatically.

The cron service is a separate Railway service from the web app —
both deploy from this repo, but only the web service has a public
domain.  The cron service wakes up at the scheduled time, runs the
rake task once, and exits.

### Local manual send

```
DISABLE_SPRING=1 bundle exec rake morning_mailer:daily
```

(Needs the SMTP env vars set locally too — easiest is a `.env`
that mirrors the Railway cron service's variables.)

## Preview & cache

- **Web preview**: `/morning_report` (or
  `/morning_report?date=YYYY-MM-DD` for a historical run).
- **Cache key**: `morning_report:<date.iso8601>`, 24-hour TTL.
- **Force rebuild**: `?refresh=1` query param, or
  `MorningReport.for(date: ..., force: true)`.
- **Test environment**: cache backend is `:null_store` (see
  `config/environments/test.rb`), so spec runs always build a
  fresh report.
