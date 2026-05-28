# Solid Queue adoption

**Status:** planning. Not yet implemented.
**Branch when implementation starts:** `feature-solid-queue`
(this doc) → a single PR that lands the adapter switch, the Puma
plugin, and the move of every existing cron-driven recurring task
into a `config/recurring.yml` entry.

This document is the design and migration plan for replacing the
project's growing collection of Railway cron services with a
single in-Puma Solid Queue supervisor. It also catalogs the
synchronous code paths that would become noticeably better with
durable queueing once Solid Queue is in place — those are followups,
not part of the adoption PR itself.

## Motivation

### Where we are

ActiveJob currently runs on the default `:async` adapter (the
commented-out `config.active_job.queue_adapter` line in
[`config/environments/production.rb`](../config/environments/production.rb)
is the only configuration). Jobs that are enqueued via
`SomeJob.perform_later` execute in a Puma worker thread. There is
no queue persistence, no retry, no scheduler.

Recurring work runs as **separate Railway cron services** that
deploy from this repo and boot Rails once per fire:

| Service | Cadence | Boots/day | Compute (boot+job)¹ |
|---|---|---|---|
| `morning_mailer:daily` | 2×/day (12 UTC + 13 UTC, DST workaround²) | 2 | ~60 s/day |
| `branches:sync` | every 15 min | 96 | ~48 min/day |

¹ Rough estimate. Rails boot dominates each fire; the actual
work (one Octokit call + a few UPDATEs, or a digest render + one
HTTPS POST to Resend) is sub-second.

² The cron scheduler evaluates schedules in UTC regardless of
the service's `TZ` env var, so the morning mailer fires at both
12 UTC (EDT) and 13 UTC (EST) and the rake task short-circuits
when local Eastern hour isn't 8. See
[`docs/morning-mailer.md`](morning-mailer.md) for the full
explanation.

### Where we're going

Two recurring tasks today, and the dispatcher + claims feature
(see [`docs/dispatcher-and-claims.md`](dispatcher-and-claims.md))
adds at least one more — `claims:sweep` is meant to fire every
~5 minutes so claim status is wall-clock-accurate for the
commits-index "pending" tile and the future GitHub-status feature.
Adding a third cron service to the stack would mean another ~288
container boots/day for ~10 seconds of actual work, and every
subsequent recurring task multiplies the bill.

The right answer is to consolidate. Solid Queue ships as a
first-class dependency of Rails 8 with native support for both
queued jobs and recurring schedules via `config/recurring.yml`.
Running it inside the existing Puma process via the `solid_queue`
Puma plugin means **one Railway service, one deploy artifact, one
log stream** — and adding a recurring task becomes a one-stanza
PR rather than a Railway dashboard change.

## Target architecture

### In-process via the Puma plugin

Opt in from [`config/puma.rb`](../config/puma.rb):

```ruby
plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"] == "true"
```

The env-var gate keeps development and test environments clean —
no surprise background processing on `bin/rails server`. Production
opts in via Railway env config.

When Puma boots in production, the plugin starts Solid Queue's
supervisor as a side process under the Puma master. Solid Queue
forks worker subprocesses from there; the scheduler (which
dispatches recurring jobs from `config/recurring.yml`) runs in the
same supervisor. Everything terminates cleanly on `SIGTERM`, so
Railway's deploy-restart-and-re-up cycle does the right thing.

### Why in-Puma over a separate worker service

For MESATestHub specifically, the trade-offs all point to shared:

| Concern | Verdict |
|---|---|
| Memory | Solid Queue's worker process holds the Rails autoloader the same as Puma; ~150–200 MB of headroom on the existing container is plenty. |
| Job throughput stealing web cycles | Workload is HTTP-out (Octokit, Resend) + DB UPDATEs. Both I/O-bound, low traffic. They won't fight. |
| Deploy restarts kill in-flight jobs | Solid Queue requeues unfinished work on supervisor restart — *more* robust than today's `:async`-in-Puma-thread, not less. |
| Can't scale workers separately from web | True. Not relevant at MESATestHub's scale; the current `:async` adapter already has this property and it's never been a problem. |
| Single point of failure | True, but on Railway the web *is* already the SPOF — if Puma dies, the cron services can't reach the DB through your app anyway. |

A separate worker service is the right call only if (1) job
workload is expected to dominate web traffic — definitely not the
case here — or (2) job failures need SLO-grade isolation from web
failures. Overkill for a solo-maintainer app where both restart
together anyway.

### Queue storage: same Postgres

Solid Queue creates ~12 `solid_queue_*` tables. Putting them in
the existing `mesatesthub_production` database is the simplest
shape and avoids a second Railway Postgres service. The rows are
small (~100 bytes each) and the workload is recurring + bursty,
not steady-state — disk and IOPS impact is negligible at this
scale. A separate queue DB is the "production-ready" answer for
apps where queue traffic is high enough to skew the main DB's
statistics or compete for connections; that's not the situation
here.

## Migration steps

1. `bundle add solid_queue`
2. `bin/rails solid_queue:install` — generates the migration for
   the `solid_queue_*` tables (jobs, ready_executions,
   claimed_executions, scheduled_executions, recurring_tasks,
   recurring_executions, semaphores, blocked_executions,
   processes, pauses, failed_executions, blocked_executions).
3. Run the migration on dev + test.
4. Switch `config.active_job.queue_adapter = :solid_queue` in
   [`config/environments/production.rb`](../config/environments/production.rb).
   Development can stay on `:async` so `bin/rails server` doesn't
   require any opt-in; test stays on `:test`.
5. Author [`config/queue.yml`](../config/queue.yml) (worker pool
   config — start with one worker, one thread per CPU) and
   [`config/recurring.yml`](../config/recurring.yml) (the
   recurring-task schedule; see the next section).
6. Opt-in the Puma plugin (see code snippet above) and add the
   `SOLID_QUEUE_IN_PUMA=true` env var to the Railway web service.
7. Migrate the existing two rake tasks to recurring jobs (see
   below) and delete the corresponding Railway cron services.
8. Update [`docs/morning-mailer.md`](morning-mailer.md) to point
   at the new deployment shape.

The migration is a single PR off `master`. The dispatcher + claims
branches (`feature-claims-schema`) rebase on top of it before
merging so `claims:sweep` ships as a recurring job rather than as
a third Railway cron service.

## Recurring tasks to migrate

### `morning_mailer:daily` → `MorningMailerJob` recurring

Today: [`lib/tasks/morning_mailer.rake`](../lib/tasks/morning_mailer.rake)
short-circuits when Eastern hour isn't 8 and otherwise calls
`MorningMailer.daily.deliver_now`. The DST workaround (two UTC
fires, one of which short-circuits) was a Railway cron limitation.

Tomorrow: a single recurring entry, still fired twice in UTC for
the same DST reason — Solid Queue's scheduler also evaluates in
UTC:

```yaml
# config/recurring.yml
production:
  morning_mailer:
    class: MorningMailerJob
    schedule: "0 12,13 * * *"
```

`MorningMailerJob#perform` keeps the same Eastern-hour guard the
rake task uses today. The mailer itself becomes
`MorningMailer.daily.deliver_later` so a transient Resend hiccup
on a Wednesday morning is a single mailer retry, not a missed
digest.

### `branches:sync` → `BranchReconcileJob` recurring

Today: [`lib/tasks/reconcile_branches.rake`](../lib/tasks/reconcile_branches.rake)
calls `Branch.reconcile_with_github`. Cron fires it every 15 min.

Tomorrow:

```yaml
# config/recurring.yml
production:
  branch_reconcile:
    class: BranchReconcileJob
    schedule: "*/15 * * * *"
```

`BranchReconcileJob#perform` calls `Branch.reconcile_with_github`.
Same operation, no Rails-boot tax.

### `claims:sweep` → `ClaimSweeperJob` recurring (new)

From the dispatcher + claims feature. Phase B already shipped
`Claim.sweep_expired!` as a model method and `claims:sweep` as a
rake task wrapper. Tomorrow:

```yaml
# config/recurring.yml
production:
  claim_sweep:
    class: ClaimSweeperJob
    schedule: "*/5 * * * *"
```

The rake task stays around as the manual / debugging entry point;
the recurring job is the production driver. `Claim.sweep_expired!`
itself doesn't change.

## Synchronous code paths worth converting

These are NOT part of the adoption PR — adopting Solid Queue
should be a focused change. But each of these becomes meaningfully
better once durable queueing is available. List them here so
they're easy to grab as follow-up slices.

### Submission scalar refresh

The strongest candidate. [`Submission#after_commit
:update_commit`](../app/models/submission.rb) currently does
~5 queries per TCC × ~500 TCCs = ~2,500 sequential queries on an
`entire`-shape submission. That's where the request stalls;
instance INSERTs are bulk-friendly and fast.

The pragmatic shape:
- Keep auth + instance saving synchronous so the response can still
  carry the saved rows (mesa_test contract stays intact)
- Move the `update_commit` body — TCC scalar refresh + commit
  scalar refresh + the new Phase B `fulfill_claim` call — into a
  `RefreshSubmissionScalarsJob`
- Submission save returns; the matrix / dashboard / claim status
  catches up a few seconds later

### Bulk submission destroy

[`ComputersController#destroy_submissions`](../app/controllers/computers_controller.rb)
ties up a request for the duration of the cascade (each destroy
fires the TCC + commit scalar refresh chain). Classic "long-
running destructive action" candidate: click delete, get
immediate feedback, scalars catch up in the background.

### Branch deletion's orphan cleanup

Today there's a subtle and somewhat dangerous gap:
[`BranchSyncJob#handle_deletion`](../app/jobs/branch_sync_job.rb)
itself is fine — it `delete_all`s memberships and `delete`s the
branch, two cheap operations. The expensive part is
[`db:cleanup_orphaned_commits`](../lib/tasks/cleanup_orphaned_commits.rake),
which is invoked separately (manually today; the user mentioned
historic RAM problems running it after big branch deletions).

The cleanup task `pluck(:id)`s every orphaned commit, every TCC
on those commits, every test_instance on those TCCs, and every
instance_inlist on those test_instances into a single Ruby array
before issuing the cascading deletes. For a feature branch with
thousands of commits each carrying hundreds of TCCs and many test
instances, that's potentially millions of integers held in memory
at once — exactly the RAM spike pattern the user saw historically.

The Solid Queue–enabled fix has two halves:

1. **Make the cleanup bounded per batch.** Refactor
   `cleanup_orphaned_commits` to process orphans in chunks of
   ~100 commits at a time, releasing memory between chunks. This
   is a pure refactor; doesn't require Solid Queue, just easier
   to justify alongside it.
2. **Enqueue the cleanup from `handle_deletion`** so it runs
   automatically after a branch deletion webhook fires, rather
   than waiting for someone to remember to run the rake task.
   With Solid Queue's persistence, even a deploy mid-cleanup is
   recoverable.

Whether to ship the per-batch refactor as part of the adoption PR
or as its own follow-up depends on how recent / acute the RAM
issue is. If branches are being deleted on the regular and prod
is feeling it, fold it in. If not, separate PR for review
hygiene.

### Mailer `deliver_later`

Free win as part of the morning-mailer migration: switch from
`MorningMailer.daily.deliver_now` to `.deliver_later`. A
transient Resend failure becomes a queued retry instead of a
missed digest day.

## What stays synchronous

Anything user-interactive (test search, page renders, log
proxies) — users are waiting for the answer. Queueing adds
latency rather than removing it.

Anything tiny (single-row UPDATEs that the user is waiting on).
The Phase B `Claim#fulfill!` call is one indexed UPDATE; queueing
it would cost more than running inline. Same for the existing
auth + computer + commit lookups in the submissions endpoint.

Commit ingest. Already async via `BranchSyncJob`. The fan-out
into `api_update_test_cases` happens *inside* the job, which is
the right shape.

## Open questions

1. **Worker pool sizing.** Start with one worker, one thread per
   CPU? Or one worker, one thread (since the workload is I/O-
   bound and Ruby's GVL means more threads don't help with
   CPU work)? Likely the former for safety; tune from production
   metrics.
2. **Recurring job concurrency control.** If a 15-minute
   `branch_reconcile` run somehow stretches past 15 minutes,
   Solid Queue will fire a second one. That's likely fine — the
   underlying `Branch.reconcile_with_github` is idempotent —
   but worth confirming during the migration spec pass.
3. **Failed-job alerting.** Solid Queue's `solid_queue_failed_
   executions` table records failures but nothing surfaces them
   today. Probably want a once-a-day "you have N failed jobs"
   notification, possibly via the morning mailer's existing
   plumbing.

## Related docs

- [`docs/morning-mailer.md`](morning-mailer.md) — needs an update
  to point at the recurring-job deployment shape after this
  migration lands.
- [`docs/dispatcher-and-claims.md`](dispatcher-and-claims.md) —
  Phase B (claim creation + sweeper) lands on top of this
  migration so `claims:sweep` ships as a recurring job rather
  than a third Railway cron service.
- [`docs/roadmap.md`](roadmap.md) — modernization timeline; this
  is the natural follow-up to Phase 4's frontend rewrite and the
  Rails 8 upgrade.
