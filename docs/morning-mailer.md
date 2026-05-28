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
- **[`app/jobs/morning_mailer_job.rb`](../app/jobs/morning_mailer_job.rb)**
  `MorningMailerJob` — the production driver. A Solid Queue
  recurring task (see [`config/recurring.yml`](../config/recurring.yml))
  fires it twice in UTC; the job carries the 8-AM-Eastern guard and
  calls `MorningMailer.daily.deliver_later`. See
  [`docs/solid-queue-migration.md`](solid-queue-migration.md).
- **[`lib/tasks/morning_mailer.rake`](../lib/tasks/morning_mailer.rake)**
  `morning_mailer:daily` rake task — the manual / debugging entry
  point (`FORCE=1` to send regardless of clock). No longer the
  scheduled driver.

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

## Email provider — Resend (HTTPS API, not SMTP)

Delivery goes through Resend's REST API over HTTPS via the
[`resend`](https://github.com/resend/resend-ruby) gem's
ActionMailer adapter, **not** SMTP.  Railway blocks outbound SMTP
on every port we tried (465 / 587 both hit `Net::OpenTimeout` at
the TCP-connect stage); HTTPS isn't blocked.  Same
`MorningMailer.daily.deliver_now` call site, different wire format.

If you ever move off Railway to a host that *does* allow outbound
SMTP, swapping back is reverting the
[`app/mailers/application_mailer.rb`](../app/mailers/application_mailer.rb)
change to set `delivery_method = :smtp` with `smtp_settings`
pointing at the provider.

### Required env vars

Since the digest now runs as a Solid Queue recurring job inside the
**web service's** Puma process (no separate cron service), these
just need to be present on the web service — most already are:

| Var | Purpose |
|---|---|
| `RESEND_API_KEY` | API key from Resend's dashboard. |
| `DATABASE_URL` | The Railway Postgres service. |
| `SECRET_KEY_BASE` | Required for Rails to boot. |
| `GIT_TOKEN` | Optional but recommended — without it, the digest shows "couldn't check" for the release-blocker line. |
| `RAILS_ENV` | `production` (gates the `:resend` delivery method — see [`application_mailer.rb`](../app/mailers/application_mailer.rb)). |
| `SOLID_QUEUE_IN_PUMA` | `true` — starts Solid Queue's supervisor + scheduler inside Puma so recurring jobs actually fire. See [`config/puma.rb`](../config/puma.rb). |

`MorningMailerJob`'s 8-AM-Eastern guard reads
`Time.now.in_time_zone('America/New_York')` explicitly, so it does
**not** depend on a `TZ` env var. Old `SMTP_*` env vars from the
SMTP era can be removed; they're no longer read.

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
Solid Queue's scheduler evaluates `config/recurring.yml` schedules
in UTC, and 8 AM ET moves between 12 UTC (EDT) and 13 UTC (EST)
twice a year.  To get a stable 8 AM ET delivery across DST without
manual schedule edits, we fire **twice** in UTC and let
`MorningMailerJob` itself decide whether it's actually 8 AM Eastern.

### Solid Queue recurring task

The digest is now scheduled in-process by Solid Queue, not by a
separate Railway cron service.  The stanza in
[`config/recurring.yml`](../config/recurring.yml):

```yaml
production:
  morning_mailer:
    class: MorningMailerJob
    schedule: "0 12,13 * * *"
```

fires `MorningMailerJob` at 12:00 UTC *and* 13:00 UTC.  The job's
`perform` checks `Time.now.in_time_zone('America/New_York').hour`
and **returns without delivering** when the local Eastern hour
isn't 8.  Net effect: during EDT (UTC-4) the 12 UTC fire delivers
and the 13 UTC fire skips; during EST (UTC-5) the 12 UTC fire skips
and the 13 UTC fire delivers.  Always 8 AM ET, no DST babysitting.

The job calls `MorningMailer.daily.deliver_later`, so a transient
Resend hiccup becomes a queued mailer retry rather than a missed
digest day.

This runs inside the web service's Puma process (the `solid_queue`
Puma plugin, gated on `SOLID_QUEUE_IN_PUMA=true` — see
[`config/puma.rb`](../config/puma.rb) and
[`docs/solid-queue-migration.md`](solid-queue-migration.md)).  There
is no longer a dedicated cron service to maintain; deleting the old
`morning_mailer:daily` Railway cron service is part of the Solid
Queue migration.

### Local manual send

```
FORCE=1 DISABLE_SPRING=1 bundle exec rake morning_mailer:daily
```

The `FORCE=1` env var bypasses the 8-AM-Eastern guard so the task
sends regardless of local time.  Same flag works for on-Railway
manual fires from the dashboard.

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
