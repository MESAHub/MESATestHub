# Daily digest mailer

Sends a daily summary email to mesa-developers and the #testhub
Slack inbound-mail address.  Mirrors the historical "morning mail"
that the Heroku app ran, ported onto the commits-based data model
that replaced the SVN-era `Version` rows.

## Pieces

- **[`app/services/morning_report.rb`](../app/services/morning_report.rb)**
  PORO that builds the report data (see "What's in it" below).
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

## What's in it

### The window

The digest for date D covers the **24 hours ending at 8:00 AM US
Eastern on D** (`MorningReport.send_time`), so consecutive digests tile
time with no gap. Until Nov 2026 the window was midnight to midnight
UTC on D. The 8 AM send only saw the first 12-13 hours of it, and the
US working day after each send was never reported (Oct 28: 4 of 16
tested commits made it in).

### Which commits

A commit is in when anything about it arrived in the window: a
**submission** (build report or test result) or a **claim**. Keying
on test instances, as before, missed commits whose build failed
everywhere (no instances) and builds still waiting on results.

### Grouping: each commit once

Following the home page (`Branch.recently_pushed`):

1. **main**: every commit on main. A commit on main never repeats
   under other branches, so a branch that merged main doesn't drag
   main's commits along. (Before, Oct 27 rendered 40 commits as 121
   rows across 31 sections, and "Need attention" counted rows: 55 for
   13 commits.)
2. **Related-branch families**: branches joined by any shared commit
   (union-find over memberships), e.g. a stack `hydro_01 … hydro_06`.
   One section, each commit once, tagged with the branch it links
   through and "+N more".
3. **Single branches**, most recent activity first.
4. **Unattached**: commits on no branch (PR test-merge commits, or a
   push whose sync hasn't landed). They have no commit page, so no
   link.

A commit a force-push dropped (`commit_rewrites`) files under the
branch it was dropped from and links there (its page still renders
with a "no longer on this branch" banner). It lists in a compact
"Rebased away" block with an arrow to its replacement, and doesn't
count as needing attention.

Commit links go through main when the commit is on main, else the
branch pushed most recently (`Commit#preferred_branch`'s rule).

### Statuses

Pills come from `CommitState` via `CommitStateCache`, worded like the
site's `test_status_pill`: N failing / N mixed / N FPE / N checksum ≠
/ Pending / "r/t passing" (partial) / All passing / Untested. The build
badge appears only on failure ("Build failed", or "Build failed on
<computer>"). CommitState counts a computer as built if any of its
build reports succeeded, so a failed build that was then retried and
succeeded no longer reads "mixed" forever.

**Needs attention** = failing, mixed, or FPE tests, or a failed build;
each commit once, worst first, listed in the header. The stat strip
shows commits tested, commits needing attention, and computers that
submitted in the window.

The per-commit problem-test lists still come from stored TCC statuses
(refreshed a few seconds after each result).

### Anomaly detection

Compares each passing result that arrived in the window with the
**previous `COHORT_LIMIT` = 50** passing runs from before the window
(back at most `COHORT_LOOKBACK` = 180 days) with the same:

- `test_case_id`, `computer_id`
- `inlist_count` (how many inlists ran, set at ingest), `fpe_checks`
- `resolution_factor`, `omp_num_threads` (runtime scales with threads)

Inlists are counted, not read off `run_optional`: clients send that
flag whether or not a test has optional inlists, so single-inlist tests
(`make_zams`) arrive both ways and splitting on it halved their
history. Rows without an `inlist_count` (pre-migration) fall back to
the flag, as `ChecksumComparison` does.

One windowed SQL query fetches every cohort. Flagged when **all** of:

- z-score ≥ `ANOMALY_Z_THRESHOLD = 3.0`
- ratio to the cohort mean ≥ `ANOMALY_RATIO_FLOOR = 1.25`
- absolute jump ≥ `ANOMALY_MIN_DELTA`: 1 minute of runtime, 256 MB of
  memory. Memory is nearly deterministic, so its stddev is tiny and z
  alone would flag any change.

Cohorts smaller than `COHORT_MIN_SIZE = 8` are skipped.

**Two commits in a row, in branch order.** A run that clears those
thresholds is reported only when a neighboring commit on its branch,
tested by the same computer in the same comparison group, does too
(`flag_streaks`).
- **Branch:** the one the digest links the commit through.
- **Sequence:** the comparison group's commits that are members of that
  branch, sorted by `corrected_time` (`MorningReport::CommitOrder`). A
  branch's memberships cover its whole history, main's ancestors
  included, so a feature branch's first commit sits right after the main
  commit it forked from.
- **Commits on no branch** fall back to every commit in the group.

Submit time is the wrong order. A computer that alternates between two
branches, or backfills old commits, puts unrelated commits next to each
other, and a regression is about the commit before it in history.

Each commit counts once, at its lowest value, so a normal rerun of the
same commit clears it. Most single flags were one-offs. For example,
BOSE's `make_zams` rn RAM jumps from 1.6 to 2.6 GB on one commit, then
drops back on the next. On the Oct 25 – Nov 4, 2026 data, this rule cut
93 findings to 31.

**Reported once per streak.** A streak needs a commit first tested in the
window. It's skipped when two of its commits were already adjacent among
the commits tested before the window, because an earlier digest reported
it then. A lone spike from before the window is reported once a commit
next to it on the branch confirms it, whenever that commit was tested.
Each entry shows how many commits in a row it held for, and the worst
commit.

**Machine slowdowns.** When one computer has runtime streaks on
`MACHINE_SLOWDOWN_MIN_TESTS = 5` or more tests in one digest, the machine
was busy or throttled. Those runtime findings fold into one line,
`MorningReport#machine_slowdowns`: "Yale_Bouchet ran 15 tests ×1.5–1.8
slower than usual". Memory findings from that computer stay listed,
because load doesn't change memory. (Nov 4, 2026: Yale_Bouchet backfilled
week-old commits 1.5–1.8× slow on 15 tests; the section went from 39
lines to 5 plus that one.)

Metrics: `runtime_minutes`, `mem_rn`, `mem_re` (kB). The detector
used to read `runtime_seconds` / `re_time` / `total_runtime_seconds`,
which are never written, and required `runtime_seconds` to be
present, so it never flagged anything. On the Oct–Nov 2026 data it
now flags roughly 10–20 per day.

Each anomaly's test name links to the test's **Trend tab** on the
branch the digest links that commit through (`link_branch_name`),
centered on the flagged commit (`?center=`), plotting the flagged metric
(`?metric=runtime_minutes|mem_rn|mem_re`). `?computer=` makes the
chart draw that computer's configs even when they aren't among the
three most-run (`TestCase#trend_payload(focus_computer:)`), so the
flagged machine's line is always there. Commits on no branch fall back
to the search page.

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
- **Before today's send** (8 AM Eastern), the preview is built live
  with the window ending now and is not cached, so looking at it early
  can't freeze what the email sends.
- **After the send**: cached under `morning_report:v<CACHE_VERSION>:<date>` for 24
  hours, so the email and the preview agree. The cached report holds
  the states *at build time*; later results on those commits don't
  change it. `?refresh=1` (or `MorningReport.for(date:, force: true)`)
  rebuilds it with current states, same window.
- **Test environment**: cache backend is `:null_store` (see
  `config/environments/test.rb`), so spec runs always build a
  fresh report.
