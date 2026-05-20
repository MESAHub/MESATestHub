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
**Status:** in progress
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

## Phase 4 — Frontend modernization

**Branch:** `frontend-tailwind`
**Status:** not started
**Estimate:** 4–8 days (incremental, page by page; less now that
CoffeeScript was pulled forward to Phase 1.5)

Goal: drop the rest of the legacy frontend stack in favor of a modern one.

**Out:**
- Bootstrap 4 → Tailwind CSS
- jQuery → vanilla JS (and/or Stimulus, see below)
- Turbolinks → Turbo
- Sprockets-driven JS bundling → importmap-rails or jsbundling-rails
- `uglifier`, `sassc-rails`, `jquery-rails`, `bootstrap`, `bootstrap_form`

**On jQuery specifically:** the only reason it's still here is that
Bootstrap 4 requires it (`.collapse('show')`, `.tooltip()`). Once Bootstrap
leaves, the converted JS in `app/assets/javascripts/*.js` uses jQuery only
for trivial DOM/event/AJAX patterns that map 1:1 to modern native APIs
(`querySelectorAll`, `addEventListener`, `classList`, `fetch`,
`dataset`, etc.). No jQuery-specific plugins (Select2, DataTables, etc.)
are in use, so the cutover is mechanical.

**Recommended JS approach for this phase:** since Rails 8 is the Phase 2
target and Hotwire is the Rails 8 default, lean on **Stimulus + Turbo**
rather than ad-hoc vanilla JS. Stimulus organizes per-page behavior
declaratively (`data-controller="commits"`,
`data-action="click->commits#togglePassing"`) which maps cleanly onto
the existing module structure (`TogglePassing`, `NearbyCommits`, etc. in
`commits.js`). Pure vanilla is also fine if Stimulus feels like
overkill; for this codebase's complexity either works.

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
- **Column visibility on `test_case_commits#show` does not persist across
  reloads.** The JS writes a cookie when a column is toggled, but on next
  load the columns reset to the default set. Either the cookie name doesn't
  match what the server reads, or the server never reads it. Phase 3 or
  Phase 4 candidate. Fixing this is also a good opportunity to migrate the
  state from cookies to URL params or localStorage.
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
