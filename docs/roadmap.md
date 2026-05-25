# MESATestHub roadmap

Sequenced plan for modernizing the codebase, captured so individual sessions
have continuity across context boundaries. Update the **Status** for each
phase as work lands.

## Operating principles

- **One branch per phase.** Long-running branches hide bugs and stall reviews.
- **Tests first, then changes.** The codebase has effectively no test coverage;
  any non-trivial change should land alongside the regression test that would
  have caught its failure mode.
- **Phases are sequential, not parallel.** Resist the temptation to interleave
  the upgrade with the frontend refactor — debugging gets ambiguous fast.
- **Email migration and small features can slot in between phases.** They're
  not on the critical path.

## Phase 1 — Test foundation

**Branch:** `tests/api-foundation`
**Status:** complete (then continuously grown alongside later phases)
**Estimate:** 1–2 days

The goal is a *small* characterization suite, not comprehensive coverage. ~12
specs targeting the highest-leverage paths, plus CI:

- Auth flow (login/logout/protected pages)
- Submissions API (`SubmissionsController#create`, `#request_commit`) —
  happy path + error cases
- GitHub webhook (`GithubWebhooksController#create`) — canned payload smoke
- Page renders for `commits#show`, `test_cases#show`, `test_case_commits#show`
- 1–2 model specs for the gnarliest methods in `commit.rb`
- GitHub Actions workflow running `bundle exec rspec` on push + PR

Existing Cucumber suite under `features/` and `spec/features/` has been
moved to `features.deprecated/` and `spec/features.deprecated/`. RSpec
request specs replace it.

## Phase 1.5 — Drop CoffeeScript

**Branch:** `frontend/drop-coffeescript`
**Status:** complete
**Estimate:** 0.5–1 day

Pulled forward from Phase 4 (frontend modernization) to de-risk the Rails 8
jump. The real CoffeeScript footprint is 4 files / ~326 lines of
jQuery-style DOM manipulation, plus 7 empty placeholder files. Convert the
4 real files to ES2015+ JavaScript, delete the empty ones, drop the
`coffee-rails` and `barista` gems. The page-render specs from Phase 1
catch the most obvious regressions; manual click-through in dev covers
the rest.

When this phase closes, the Rails 8 step in Phase 2 stops having a
gem-resolver risk path.

## Phase 2 — Rails 6.1 → 8.0 upgrade

**Branch:** `rails-upgrade`
**Status:** complete
**Estimate:** 2–4 days (with Phase 1 tests in place and Phase 1.5 done)

See [`docs/rails-upgrade.md`](rails-upgrade.md) for the detailed phased plan,
including the `load_defaults` 5.1 catch-up that has to happen before the Rails
7 jump, the two mandatory `update_attributes` → `update` fixes, and the
gem-by-gem compatibility table.

Target end state is **Rails 8.0** rather than 7.2 — the marginal cost of one
extra version bump is small once the deprecation churn for 6.1→7.x is done,
and 7.2 is in maintenance support while 8.x is the actively-developed line.
Solid Queue (Rails 8 default) is also the natural fit for the Phase 3 GitHub
sync background-job rewrite.

Each sub-phase (5.1→5.2 defaults, 5.2→6.0, 6.0→6.1, 6.1→7.0, 7.0→7.1,
7.1→7.2, 7.2→8.0) lands as its own commit. CI gating prevents regressions.

When this phase closes, the 12 remaining Dependabot advisories close with it.

_Coffee-rails risk was eliminated by completing Phase 1.5 first._

## Phase 3 — Performance and bug fixes

**Branch:** `perf-github-sync`
**Status:** complete
**Estimate:** 2–3 days

Known issues to address:

- ~~**GitHub sync after every webhook push is slow.**~~ Done. The webhook
  now enqueues a `BranchSyncJob` and returns immediately. ActiveJob's
  default `:async` adapter is fine for this scale; swap in Solid Queue
  later if the queue needs durability.
- ~~**Deleting branches from GitHub causes errors.**~~ Done.
  `Branch.api_update_branches`'s deletion path is now wrapped in a
  transaction and covered by seven regression specs; the
  cascading-delete hypothesis didn't reproduce in any scenario.
- ~~**General N+1 audit on the commit show page**~~ Done. `Commit#computer_info`
  was doing ~4 queries per unique spec on commits/show — rewritten to batch
  the lookups, plus `compile_stati` is now memoized so the
  `compilation_status` / `compile_success_count` / `compile_fail_count`
  trio that the show action calls back-to-back hits the database once
  instead of three times. Behavior + query-count regression specs at
  [`spec/models/commit_computer_info_spec.rb`](spec/models/commit_computer_info_spec.rb).
- ~~**Upgrade Octokit 4 → 10.**~~ Done. Drop-in bump — the
  middleware-contract concern in the original plan turned out to be
  unfounded; the current Octokit README still shows the exact
  `Octokit.middleware = stack` pattern that
  [`app/models/application_record.rb`](app/models/application_record.rb)
  uses, and none of the breaking changes in 5/6/7/8/9/10 touch the
  endpoints this app calls. Backed by a new wiring spec at
  [`spec/models/github_api_wiring_spec.rb`](spec/models/github_api_wiring_spec.rb).

Doing this after the upgrade gives access to Rails 7.1's async query loading
and improved background-job tooling.

## Phase 3.5 — GitHub sync overhaul

**Branch:** `perf-sync-topology`
**Status:** complete
**Estimate:** 4–6 days (actual: ~consistent with that)

See [`docs/sync-overhaul.md`](sync-overhaul.md) for the full plan.

The Phase 3 sync work moved the GitHub fan-out off the webhook request
path but didn't reduce the underlying API-call count. This phase
replaces the position-based ordering scheme with a stored commit
topology (`commit_relations` join table) and rewrites the sync flow to
consume the webhook payload + `compare(before, after)` directly.

Outcomes delivered:

- Commit ordering on each branch matches what
  `github.com/MESAHub/mesa/commits/{branch}` shows, driven by a
  recursive CTE over `commit_time`.
- Typical-push sync cost dropped from "100+ commits fetched and
  repositioned per branch + 3 content calls per new commit" to
  "one `api.compare` call per push, plus zero (copy-from-parent) or
  three (api fetch) content calls per *source-touching* commit." The
  vast majority of pushes don't touch source files at all.
- `branch_memberships.position` and the orphaned `commits.parents_count`
  / `commits.children_count` counter columns dropped from the schema.
- `Branch.reconcile_with_github` (rake `branches:sync`) covers
  missed-webhook recovery and deploy-day catch-up by dispatching
  synthetic events through the same `BranchSyncJob` path.
- `topology:backfill` and `test_cases:populate` rake tasks for the
  one-time historical population.

Suite grew from 78 to 158 specs over this phase.

## Phase 4 — Frontend modernization

**Branch:** `frontend-tailwind`
**Status:** complete

Replaced the entire legacy frontend stack (Bootstrap 4, jQuery,
Sprockets-driven JS, Turbolinks, custom SCSS, font-awesome,
bootstrap_form, high_voltage) with Tailwind v4 + Turbo +
Stimulus + Importmap. Every user-facing HTML page now renders
through `app/views/layouts/modern.html.haml`; there is no
legacy layout, no second JS pipeline, and no Bootstrap.

See [`docs/frontend-modernization.md`](frontend-modernization.md)
for the step-by-step record of how each page was migrated, and
[`docs/design_handoff_mesa_testhub/`](design_handoff_mesa_testhub/)
for the visual reference that drove the design decisions.
CLAUDE.md's "Frontend architecture" section captures the
current state and the design primitives an agent needs.

**Known follow-up — not blocking Phase 5:**

- ~~`TestInstance.query` rot.~~ Fixed on
  `fix-test-instances-search`. Dropped the dead `version:`
  option (depended on the dropped `mesa_version` column /
  retired `Version` model). Wired up `rn_runtime:` and
  `re_runtime:` SearchOptions that the help text had been
  promising. Documented the already-working `commit:` and
  `commit_datetime:` fields (the latter accepts ranges like
  `2024-01-01-2024-06-30`), and removed the warning banner.

## Daily digest mailer

**Branch:** `feature-morning-mailer-revival`
**Status:** complete

Resurrected the daily mesa-developers digest on the commits-based
data model. The old `morning_email_*` methods were welded to the
dropped `Version` model and the `mesa_version` column; the new
pipeline is a `MorningReport` PORO + a clean `MorningMailer#daily`
action + a pretty HTML template that matches the app's light/dark
design system. Adds:

- Per-commit pass/fail/checksum/mixed roll-ups grouped by branch
  (main first).
- Performance anomaly detection: flags passing instances whose
  runtime or RAM is ≥ 3σ AND ≥ 1.25× the recent
  `(test_case, computer, run_optional, fpe_checks)` cohort
  mean. Drill-in URLs land on `test_instances#search` with a
  pre-populated `commit_datetime:` window.
- An in-browser preview at `/morning_report` (24-hour
  `Rails.cache` per date, `?refresh=1` to bust).
- Configurable for Railway cron at 8 AM US Eastern via
  `TZ=America/New_York` + `0 8 * * *` schedule.

See [`docs/morning-mailer.md`](morning-mailer.md) for the
architecture overview, the anomaly-detection knobs
(`COHORT_LIMIT` / `ANOMALY_Z_THRESHOLD` / `ANOMALY_RATIO_FLOOR`),
and the Railway cron setup.

## Ongoing — email migration

**Status:** deferred, not blocking
**Estimate:** 0.5 days

The current Heroku-Mailgun add-on credentials will stop working once the
Heroku app is destroyed. Migrate to a direct-signup email provider
([decision deferred — Brevo, Resend, Mailgun-direct, or SendGrid-direct](#)).
Update the SMTP env vars on Railway; no application code change required
since the mailer uses generic SMTP settings.

## Feature backlog

To be sequenced after Phase 2 (modern Rails unlocks the most flexibility).
Add items here as they come up so they don't get lost.

- _(none yet — placeholder for future work)_

## Bugs surfaced by Phase 1 specs (fixed in Phase 3)

All three landed at the head of the `perf-github-sync` branch, each with a
regression spec:

- `Commit.test_candidate` no longer infinite-recurses when `Branch.main` is
  nil. Drive-by: removed three stale debug `puts`, one of which referenced
  an undefined `Submissions` constant and crashed the fallback path.
- `_commit.json.jbuilder` now skips the `url` field when a commit has no
  branch memberships yet, instead of raising on `commit_url(nil, ...)`.
- `Branch#nearby_test_case_commits` returns just the seed TCC when the
  membership has a `nil` position, instead of raising on `position + 1`.

## Bugs/UX issues surfaced during Phase 1.5 smoke testing

All preexisting (present on Heroku too); not regressions from the JS
conversion. Captured here so they don't get lost.

- ~~**`test_instances#search` is broken.**~~ Fixed in Phase 3. Four bugs
  in `TestInstance.query`: empty input raised `NoMethodError`, the
  `runtime` option pointed at a non-existent column, and bad date /
  datetime values crashed instead of going on the failures list. The
  documented `version` option is still commented out in the model
  (no `mesa_version` column exists any more) — the help text should
  drop that bullet during Phase 4.
- ~~**Column visibility on `test_case_commits#show` does not persist across
  reloads.**~~ Fixed by the Phase 4 / Step 7 port — the modern test-on-commit
  page persists its column picker state to
  `localStorage["mesa.test_on_commit.columns.v1"]` instead of relying on
  the legacy cookie machinery.
- **`#passing` / `#missing` collapse animation feels clunky.** Expansion is
  instantaneous, followed by a smooth scroll — disorienting. Bootstrap 4's
  `.collapse` plugin should do a smooth transition; needs investigating
  whether a CSS rule is overriding the transition, or whether the
  scroll-on-`shown.bs.collapse` is firing before the collapse animation
  starts. Phase 4 candidate — likely fixes itself with the Bootstrap →
  Tailwind migration.
- **`commits.js`'s `BuildLog` and `test_case_commits.js`'s `TestLogs`
  HEAD probes are CORS-blocked on Railway.** Will resolve when
  `testhub.mesastar.org` (already on the Flatiron CORS allowlist) is
  repointed at Railway. No code change required from this end.

## Done

- **Frontend modernization** (Phase 4). Multi-session work on the
  `frontend-tailwind` branch. Replaced Bootstrap + jQuery +
  Sprockets-driven JS + Turbolinks + custom SCSS with
  Tailwind v4 + Turbo + Stimulus + Importmap, page by page,
  then ripped out the entire legacy stack in Step 9b. Added the
  shared `_field` / `_form_errors` form primitives, a Kaminari
  `modern` paginator theme, and a curated SVG icon set in
  `CommitsHelper#mesa_icon`. Drive-by fixes that landed during
  the phase: user-deletion cascade was finally wired up
  (`User has_many :computers, dependent: :destroy` + FK with
  `ON DELETE CASCADE`); the broken `Computer.platforms`
  reference was replaced with a `Computer::PLATFORMS` constant;
  the dead `computers#test_instances_index` page (and the dead
  `users/computers_index.html.haml` template, and the dead
  `submissions#show` HTML view) were deleted. Suite grew from
  158 to 263 specs.
- **GitHub sync overhaul** (Phase 3.5). Topology-driven sync built on
  a new `commit_relations` join table. Webhook → `BranchSyncJob`
  consumes the payload, calls `api.compare(before, after)` once,
  bulk-ingests commits + parent edges + memberships, and uses the
  webhook's per-commit file-change list to decide between copying
  test cases from the parent (zero API calls) or re-fetching via
  `api.content` (three calls). `Branch#ordered_commits` uses a
  recursive CTE for the canonical reverse-chronological listing.
  `branch_memberships.position` dropped; rake tasks for
  `topology:backfill`, `branches:sync`, and `test_cases:populate`
  cover backfill, missed-webhook recovery, and existing-state cleanup.
  Suite grew from 78 to 158 specs.
- **Performance and bug fixes** (Phase 3). Fifteen commits on the
  `perf-github-sync` branch covering the four roadmap items plus four
  queued bugs: the three Phase-1-spec-discovered bugs (test_candidate
  recursion, jbuilder branchless crash, branch nearby_test_case_commits
  nil position), the test_instances#search regression suite, the
  branch-deletion regression specs, Octokit 4 → 10, the webhook → ActiveJob
  cut-over, and the commits#show N+1 elimination. Suite grew from 24 to
  78 specs.
- **Rails 6.1 → 8.0 upgrade** (Phase 2). Eight commits on the
  `rails-upgrade` branch: Phase 0 (`update_attributes` → `update`),
  Phases 1–3 (flip `load_defaults` 5.1 → 5.2 → 6.0 → 6.1), Phase 4
  (Rails 7.0 + `load_defaults` 7.0), Phase 5 (Rails 7.1 + Rack 3
  `:unprocessable_entity` → `:unprocessable_content` rename), Phase 6
  (Rails 7.2, drop `config/secrets.yml`, `show_exceptions = :none`,
  bump `database_cleaner` for the `schema_migration` API change),
  Phase 7 (Rails 8.0, bump `jbuilder` for the `ProxyObject` removal,
  drop the Cucumber gems that were holding the resolver back). All
  24 specs green throughout. Smoke-tested in dev on Rails 8.0.5.
- Migrate from Heroku to Railway hosting
- Set up Railway Postgres and restore Heroku snapshot
- Strip Heroku-specific gems (`barnes`, `scout_apm`, `rails_12factor`)
- Patch ~30 of 44 Dependabot advisories by bumping non-Rails gems
- Stop committing precompiled assets (`public/assets/` was tracked,
  causing stale-bundle serving)
- Add `faraday-retry` for Octokit retry middleware
- Remove unused `sinatra` gem
- Fix hardcoded `testhub.mesastar.org` URL in `commits.coffee`
