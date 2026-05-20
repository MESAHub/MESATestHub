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

**Branch:** `tests/api-foundation` (active)
**Status:** in progress
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
**Status:** in progress
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
**Status:** not started
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
**Status:** not started
**Estimate:** 2–3 days

Known issues to address:

- **GitHub sync after every webhook push is slow.** The current
  `GithubWebhooksController` flow synchronizes commit/branch state inline.
  Move to background jobs (ActiveJob), batch where possible, and skip
  redundant fetches.
- **Deleting branches from GitHub causes errors.** Likely a cascading-delete
  or missing-`dependent`-option issue on the Branch ↔ BranchMembership ↔
  Commit relationships. Reproduce, fix, add a regression spec.
- **General N+1 audit on the commit show page** — large commits with many
  test cases / instances likely have hot query patterns worth addressing.

Doing this after the upgrade gives access to Rails 7.1's async query loading
and improved background-job tooling.

## Phase 4 — Frontend modernization

**Branch:** `frontend-tailwind`
**Status:** not started
**Estimate:** 4–8 days (incremental, page by page; less now that
CoffeeScript was pulled forward to Phase 1.5)

Goal: drop the rest of the legacy frontend stack in favor of a modern one.

**Out:**
- Bootstrap 4 → Tailwind CSS
- Turbolinks → Turbo
- Sprockets-driven JS bundling → importmap-rails or jsbundling-rails
- `uglifier`, `sassc-rails`, `jquery-rails`, `bootstrap`, `bootstrap_form`

**In:**
- Tailwind via `tailwindcss-rails` or standalone CLI
- Native JS modules (no transpilation needed for modern browsers)
- Turbo for SPA-like interactions
- Importmap-rails for ES module loading

Best done page-by-page rather than as a single big-bang. The auth flow and
404 page are good first candidates; the commits index and show pages are
the most complex.

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

## Bugs surfaced by Phase 1 specs (queued for Phase 3)

- `Commit.test_candidate` infinite-recurses when `Branch.main` returns nil
  (`app/models/commit.rb:432`). The spec currently stubs it; the real fix
  is to guard the recursive call.
- `app/views/commits/_commit.json.jbuilder:5` calls
  `commit_url(commit.branches[0], ...)` — if a commit has no branches yet,
  this raises a route-generation error. The submissions API hits this on
  empty submissions for newly-ingested commits.
- `BranchMembership.position` can be nil, but `Branch#nearby_test_case_commits`
  ([`app/models/branch.rb:451`](app/models/branch.rb:451)) calls `position + 1`
  without a nil check, breaking the `test_case_commits#show` page for those
  memberships.

## Done

- Migrate from Heroku to Railway hosting
- Set up Railway Postgres and restore Heroku snapshot
- Strip Heroku-specific gems (`barnes`, `scout_apm`, `rails_12factor`)
- Patch ~30 of 44 Dependabot advisories by bumping non-Rails gems
- Stop committing precompiled assets (`public/assets/` was tracked,
  causing stale-bundle serving)
- Add `faraday-retry` for Octokit retry middleware
- Remove unused `sinatra` gem
- Fix hardcoded `testhub.mesastar.org` URL in `commits.coffee`
