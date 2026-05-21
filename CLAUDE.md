# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project orientation

MESATestHub is a Ruby on Rails app that tracks test results for the MESA
(Modules for Experiments in Stellar Astrophysics) stellar evolution code. Test
clients submit results via a JSON API; the web interface shows results
organized by commits, branches, computers, and test cases. GitHub webhooks
drive commit ingestion from `MESAHub/mesa`.

- **Production**: Railway (`mesatesthub-production.up.railway.app`),
  Postgres service. Heroku still runs in parallel on `testhub.mesastar.org`
  during the cutover; that domain is expected to repoint at Railway.
- **Solo maintainer**, low-but-important traffic (the MESA dev community).
  Downtime of a few days is tolerable; data integrity is not negotiable.

## Where context lives

Before doing non-trivial work, read the appropriate doc:

- **[`docs/roadmap.md`](docs/roadmap.md)** — sequenced plan for ongoing
  modernization work (test foundation → Rails 7 upgrade → perf → frontend).
  Active phase and branch are noted there. **Check this first** before
  proposing structural changes; the plan may already cover them.
- **[`docs/rails-upgrade.md`](docs/rails-upgrade.md)** — record of the
  Rails 6.1 → 8.0 upgrade (now complete on the `rails-upgrade` branch),
  including the deviations from the original phased plan that actually
  needed code changes.
- **[`docs/sync-overhaul.md`](docs/sync-overhaul.md)** — Phase 3.5
  GitHub sync rewrite (topology-driven ordering, webhook payload-driven
  sync). Complete on the `perf-sync-topology` branch.
- **[`docs/frontend-modernization.md`](docs/frontend-modernization.md)**
  — plan for the Phase 4 frontend rewrite (Bootstrap+jQuery →
  Tailwind+Turbo+Stimulus, plus port of the design in
  `docs/design_handoff_mesa_testhub/`). Spans multiple sessions on
  the `frontend-tailwind` branch. **Steps 0–5 have landed plus
  Step 6 scaffolding** — Tailwind + Turbo + Stimulus + importmap
  are installed alongside the legacy stack; the 404 page, login,
  the commits index (`/:branch/commits`), and the commit detail
  page (`/:branch/commits/:sha`) all render through the modern
  layout; `Commit#commit_state` / `#test_computer_matrix` /
  `#per_computer_summary` / `#per_test_summary` /
  `#cells_changed_since` / `#default_detail_tab` /
  `Branch#sparkline_data` / `Branch#commit_neighbors` /
  `Branch#last_clean_commit_before` /
  `TestCaseCommit#instances_for_display` aggregation helpers live
  in
  [`app/models/concerns/commit_state.rb`](app/models/concerns/commit_state.rb)
  (and the relevant Branch methods in
  [`app/models/branch.rb`](app/models/branch.rb)).
  Step 5 departed from the original handoff in a few ways — see
  the doc for the details (subway map instead of sparkline, no
  stat tiles, cursor pagination via a `before=` URL param instead
  of Kaminari, inline date-picker chip). Step 6 substep follow-ups
  (full matrix, Tests-tab search/ribbon, log streaming) are next.

When changes invalidate the plan, update the relevant doc in the same commit
that makes the change.

## Reality checks (things the codebase *looks* like but isn't)

- The app runs on **Rails 8.0** with `config.load_defaults 8.0`. The
  6.1 → 8.0 upgrade landed on the `rails-upgrade` branch as eight
  sequential commits (Phase 0 prep through Phase 7). See
  [`docs/rails-upgrade.md`](docs/rails-upgrade.md) for the deviations
  from the original plan — Rack 3's `:unprocessable_entity` →
  `:unprocessable_content` rename, `show_exceptions` becoming an enum,
  and the gems that needed bumps or removal for the resolver to settle.
- **The test suite is small but real.** 180 specs (request + model + job)
  cover auth, submissions API, GitHub webhook (now async via
  `BranchSyncJob`, payload-driven), branch deletion, the Octokit
  middleware wiring, `TestInstance.query`, `Commit#computer_info`, the
  Phase 3.5 ingestion + topology + ordering + reconcile path, and
  high-traffic page renders. They are the regression safety net for
  upcoming work — build on this rather than starting fresh.
- **No Cucumber.** The old Cucumber suite is preserved at
  `features.deprecated/` and `spec/features.deprecated/`. RSpec request
  specs replace it. Do not add `.feature` files.
- **No CoffeeScript.** All `.coffee` files were converted to plain ES2015+
  JavaScript in the `frontend/drop-coffeescript` branch. `coffee-rails` and
  `barista` are gone from the Gemfile. The remaining frontend stack
  (Bootstrap 4, jQuery, Sprockets, Turbolinks) is being replaced in Phase 4.
- **Two frontend stacks coexist during Phase 4.** Pages still using
  Bootstrap render through `layouts/application.html.haml`, which links
  Sprockets-built `application.css` (Bootstrap + custom SCSS) and
  `legacy.js` (jQuery + Bootstrap + Turbolinks + custom JS). Pages
  migrated to the new design render through
  `layouts/modern.html.haml`, which links the Tailwind v4 build at
  `app/assets/builds/tailwind.css` and loads Turbo + Stimulus via
  `importmap-rails`. Controllers opt in per-action with
  `render layout: "modern"`. The Sprockets entry point was renamed from
  `application.js` to `legacy.js` so it doesn't collide with the
  importmap entry at `app/javascript/application.js`.
- **sassc-rails's :sass CSS compressor must stay disabled.** SassC can't
  parse Tailwind v4's modern color syntax (`rgb(from red r g b)`, etc.).
  Both `config/environments/test.rb` and `config/environments/production.rb`
  explicitly set `config.assets.css_compressor = nil`. Removing or
  flipping that breaks asset compilation everywhere the modern layout
  loads.
- **Dev preview surface for Phase 4.** `/dev/preview/...` routes mount
  only in development + test (see [`config/routes.rb`](config/routes.rb)
  and [`DevPreviewController`](app/controllers/dev_preview_controller.rb)).
  Each action renders a migrated view inside `layouts/modern.html.haml`
  with canned data and bypasses the auth filter so the design can be
  reviewed in a browser without logging in. Add a new action per page
  as it migrates.
- **Tailwind rebuild after class changes.** Tailwind v4's standalone
  CLI scans view files at build time and only emits utilities it
  actually saw. After adding new utility classes to a view, run
  `DISABLE_SPRING=1 bin/rails tailwindcss:build`. The Rails dev
  server *will not* pick up new class names on its own — Sprockets
  serves the existing `tailwind.css` build until it's rewritten.
- **HAML class shorthand can't hold Tailwind brackets.** `.text-[10px]`
  in HAML's dotted-shorthand fails to parse (HAML thinks the `[` opens
  an attribute). Any utility with brackets (`text-[10px]`,
  `grid-cols-[12px_minmax(0,2.4fr)]`, etc.) must live in the explicit
  `{ class: "…" }` hash. Same goes for empty tags — write `%span &nbsp;`
  or give the tag content; bare `%span` followed by sibling tags
  trips an "illegal nesting" error.
- **Dev preview routes must mount BEFORE catch-all `/:branch/commits`.**
  The `branch: /.*/` constraint will happily consume `dev/preview` as
  a branch name. The `dev/preview/...` block lives near the top of
  `config/routes.rb`, just below the submissions routes.
- **Cursor pagination on the commits index, two URL params.**
  `commits#index` accepts two mutually-exclusive cursors:
  `?before=X` (default mental model — show commits with
  `commit_time < X`, newest first, subway map initializes at
  its newest end) and `?after=Y` (show commits with
  `commit_time > Y`, then reversed, map initializes at its
  oldest end). The `?after=` param exists so navigating from
  page N to N-1 (newer) lands the user on the older slice of
  N-1's commits — the bridge between the two pages — instead
  of skipping forward by `page_size - 12` commits. Calendar
  date picks always emit `?before=`. Parsing helpers:
  `parse_before_param` (end-of-day default) and
  `parse_after_param` (beginning-of-day) in
  [`commits_controller.rb`](app/controllers/commits_controller.rb).
  No Kaminari for this index; no `?page=` param.
- **Commit detail tabs are server-pre-rendered, not Turbo Frames.**
  `commits#show` renders every panel (Summary / Tests / Computers /
  Diff / Logs) on each request; the `tabs_controller.js` Stimulus
  controller toggles `hidden` between them and replaceState's the
  URL to `?tab=<id>`. Banner action buttons route through the same
  controller via `data-action="click->tabs#switchFromLink"`. The
  controller's `aria-selected` + border-brand updates have to stay
  in sync with `_show_tab_strip.html.haml`'s class list — both
  control the underline.
- **`Branch#last_clean_commit_before` is bounded at 25 commits.**
  Walking the recursive-CTE result and calling `commit_state` on
  each is several queries per step, so an unbounded walk on a stale
  branch could fan out. When nothing turns up the Diff tab gets
  rendered with `aria-disabled="true"` and `pointer-events-none`,
  not hidden — so users see why the comparison is missing.
- **Multi-line Ruby in HAML attribute hashes does not work.**
  Each `- …` line is its own Ruby statement; assignments,
  conditionals, and arrays must fit on one line or move to a
  helper. The tab strip's badge logic + array of tab specs lives
  in
  [`app/helpers/commits_helper.rb`](app/helpers/commits_helper.rb)
  (`tests_tab_badge`, `computers_tab_badge`,
  `computer_state_color`, etc.) precisely because trying to inline
  multi-line `case` and ternaries in HAML threw "indented N levels
  deeper than the previous line" errors.
- **No user-facing Active Storage**. The default `:local` service is
  scaffolding only. The high-severity Active Storage CVEs are unreachable
  in this codebase.
- **The Sprockets asset pipeline does not have committed compiled assets**
  any more. `public/assets/` is gitignored. Sprockets compiles fresh on
  every Railway deploy.
- **Bootsnap caches load paths** in `tmp/cache/bootsnap`. If you remove or
  rename a gem and immediately see `cannot load such file`, clear the cache
  with `rm -rf tmp/cache/bootsnap`.

## Development commands

### Setup
- `bundle install` — Ruby gems
- `yarn install` — JS deps (Node 18.x, Yarn 1.22.x)
- `bundle exec rails db:setup` — Postgres in all environments

### Run
- `bundle exec rails server` — development server
- Local DB is `development` (Postgres on `localhost:5432`). Most recent
  prod snapshot has been restored to it.

### Test
- `bundle exec rspec` — full suite. **Aim for green on every commit to
  feature branches.**
- `bundle exec rspec spec/requests/auth_spec.rb` — single file.
- CI runs the same command on push + PR via `.github/workflows/test.yml`.

### Database
- `bundle exec rails db:migrate`
- `bundle exec rails db:reset` — drop, create, migrate, seed
- To re-pull prod data:
  ```
  heroku pg:backups:capture && heroku pg:backups:download
  pg_restore --no-acl --no-owner --clean --if-exists -d development latest.dump
  ```
  (Local Postgres is via Postgres.app at
  `/Applications/Postgres.app/Contents/Versions/17/bin/`.)

### Custom Rake tasks (in `lib/tasks/`)
- `morning_mailer:send` — daily summary emails
- `update_pulls:update` — GitHub PR data
- `compute_delays`
- `cleanup_orphaned_commits`

## Architecture

### Core models
- **Commit** — Git commits from the MESA repo
- **Branch**, **BranchMembership** — branches and the join table
- **TestCase** — a single test that can run
- **TestCaseCommit** — aggregate test-case state per commit
- **TestInstance** — one execution of a test case on a specific commit + computer
- **TestDatum**, **InlistDatum**, **InstanceInlist** — per-instance metric data
- **Computer** — machines that run tests
- **Submission** — a batch of test instances from a computer
- **User** — operator of one or more computers; some are admins

### Data flow
1. GitHub webhooks (`GithubWebhooksController`) ingest commits.
2. Test clients POST results to `SubmissionsController#create` (JSON).
3. Web UI (`CommitsController`, `TestCasesController`,
   `TestCaseCommitsController`) reads from the DB.

### GitHub integration
- `octokit` for the API, `faraday-http-cache` for caching, `faraday-retry`
  for transient-error resilience.
- `GIT_TOKEN` env var = personal access token.
- Hard-coded to `MESAHub/mesa`.

## Conventions

- **Branches**: kebab-case, prefix by purpose: `tests/`, `rails-upgrade`,
  `perf-`, `frontend-`, `fix-`, `feature-`.
- **Commits**: short imperative subject, present-tense verb. Match style of
  existing `git log` (e.g., "Restrict most pages to logged-in users to
  reduce traffic"). Body when the *why* needs explanation.
- **No Co-Authored-By trailers** in commits unless explicitly requested.
- **Never commit precompiled assets** (`public/assets/`). Sprockets does this
  at deploy time.
- **Never commit DB dumps**. They get UUID-style names and slip through;
  `.dump` is gitignored.

## Environment variables

Production (Railway service):
- `RAILS_ENV`, `RACK_ENV` = `production`
- `RAILS_LOG_TO_STDOUT`, `RAILS_SERVE_STATIC_FILES` = `enabled`
- `SECRET_KEY_BASE` — random, regenerate with `bundle exec rails secret`
- `DATABASE_URL` — reference to Railway Postgres service
- `GIT_TOKEN`, `GIT_USERNAME`, `GITHUB_WEBHOOK_SECRET` — GitHub API + webhook
- `OWNER_EMAIL`, `MAILGUN_SMTP_*` — outbound mail (Mailgun via Heroku
  add-on, *to be migrated*)
- `DISABLE_SPRING` = `1` — Spring binstubs are present but must not run in
  production
- `MISE_RUBY_COMPILE` = `false` (optional) — skip from-source Ruby build
  on Railway

## Quick gotchas

- Spring is in the dev Gemfile and writes binstubs. Production runs Spring
  by accident if invoked through `bin/rails` without `DISABLE_SPRING`.
- The mailer config uses Mailgun SMTP env vars but the underlying provider
  is incidental. Switching email providers is a 4-env-var change, no code.
- `app/mailers/morning_mailer.rb` has several hardcoded
  `https://testhub.mesastar.org/...` URLs that build email body links. They
  need updating before the custom domain shifts or those emails will point
  at the old Heroku app.

## When in doubt

- Pull `docs/roadmap.md` to see what phase is active and whether the work
  in question belongs to that phase or a different one.
- Don't write tests for code that isn't on the active branch's critical
  path. The test foundation is intentionally small.
- Don't mix the upgrade with frontend changes. One axis of change per
  branch.
