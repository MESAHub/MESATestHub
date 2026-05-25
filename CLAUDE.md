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
  — record of the Phase 4 frontend rewrite (Bootstrap + jQuery
  + Sprockets + Turbolinks → Tailwind + Turbo + Stimulus +
  Importmap). **Complete** as of the legacy purge in Step 9b
  on the `frontend-tailwind` branch. The doc lists every step,
  every page, and every architectural decision; consult it when
  you need history on why a given layout / partial / helper
  looks the way it does. Active design tokens live in
  `app/assets/tailwind/application.css` and the Stimulus
  controllers under `app/javascript/controllers/`.
When changes invalidate the plan, update the relevant doc in the same commit
that makes the change.

## Frontend architecture (post-Phase 4)

Single layout: [`app/views/layouts/modern.html.haml`](app/views/layouts/modern.html.haml).
Stack: Tailwind v4 (standalone CLI, output at
`app/assets/builds/tailwind.css`), Turbo, Stimulus, Importmap.
Sprockets-rails still in place to serve the Tailwind build and
wire `tailwindcss:build` into `assets:precompile` at deploy.

Shared design primitives:

- **Reusable form fields** —
  [`app/views/shared/_field.html.haml`](app/views/shared/_field.html.haml)
  wraps label + input + inline error for `:text` / `:email` /
  `:password` / `:select` / `:checkbox` / `:textarea` /
  `:number` / `:url` / `:tel`. Top-of-form summary banner at
  [`app/views/shared/_form_errors.html.haml`](app/views/shared/_form_errors.html.haml).
- **CSS vocabulary** in
  [`app/assets/tailwind/application.css`](app/assets/tailwind/application.css):
  `.mesa-input` (with `.is-invalid` / `[aria-invalid="true"]`
  error state), `.mesa-checkbox`, `.mesa-label`, `.mesa-btn`,
  `.mesa-btn-primary`. All gated under `.mesa-modern` on
  `<body>` from an earlier "two stacks coexisting" world — the
  scope is now harmless and could be flattened in a future
  cleanup but it isn't blocking anything.
- **Inline SVG icons** via `mesa_icon(name, size:, css:)` in
  [`CommitsHelper`](app/helpers/commits_helper.rb) — small
  curated set (check / x / chevron / arrow_left / search / warn
  / plus / file / github / etc.). Replaces font-awesome.
- **Pagination** via the `modern` Kaminari theme at
  [`app/views/kaminari/modern/`](app/views/kaminari/modern/).
  Pages opt in with `paginate @scope, theme: "modern"`.
- **Turbo wrinkles** the agent will hit:
  - Form re-renders on validation failure MUST use
    `status: :unprocessable_content` (or `:unprocessable_entity`
    on Rack 2). Turbo silently no-ops the default 200 + render
    pattern and the user sees no feedback.
  - Destructive actions use `button_to` (Turbo-aware) instead of
    `link_to method: :delete` — the legacy `data-method=delete`
    via rails-ujs is no longer loaded.

The detailed history of how each page was migrated lives in
[`docs/frontend-modernization.md`](docs/frontend-modernization.md).
Reach for it when you need to understand *why* a particular
helper or partial exists.

## Reality checks (things the codebase *looks* like but isn't)

- The app runs on **Rails 8.0** with `config.load_defaults 8.0`. The
  6.1 → 8.0 upgrade landed on the `rails-upgrade` branch as eight
  sequential commits (Phase 0 prep through Phase 7). See
  [`docs/rails-upgrade.md`](docs/rails-upgrade.md) for the deviations
  from the original plan — Rack 3's `:unprocessable_entity` →
  `:unprocessable_content` rename, `show_exceptions` becoming an enum,
  and the gems that needed bumps or removal for the resolver to settle.
- **The test suite is small but real.** 263 specs (request + model +
  helper + job) cover auth, submissions API, GitHub webhook (now
  async via `BranchSyncJob`, payload-driven), branch deletion, the
  Octokit middleware wiring, `TestInstance.query`,
  `Commit#computer_info`, the Phase 3.5 ingestion + topology +
  ordering + reconcile path, the test_cases#show branch-scoped
  helpers (`#commit_window`, `#status_summary_for`,
  `#trend_payload`) + the `TestCasesHelper#submissions_payload`
  picker logic, the computers#show bulk-delete + filter +
  permissions matrix, the Submission destroy cascade scalar
  refresh, the User destroy cascade chain, and high-traffic page
  renders. They are the regression safety net for upcoming work —
  build on this rather than starting fresh.
- **No Cucumber.** The old Cucumber suite is preserved at
  `features.deprecated/` and `spec/features.deprecated/`. RSpec request
  specs replace it. Do not add `.feature` files.
- **No CoffeeScript / Bootstrap / jQuery / Turbolinks / Sprockets-pipeline
  legacy.** All `.coffee` files were converted to plain ES2015+
  JavaScript in the `frontend/drop-coffeescript` branch. The
  Bootstrap + jQuery + Sprockets + Turbolinks stack itself was
  ripped out in Phase 4 Step 9b (commits leading up to `bf21d3f`
  on `frontend-tailwind`). The only frontend stack now is the
  one described in the "Frontend architecture" section above.
- **Tailwind rebuild after class changes.** Tailwind v4's standalone
  CLI scans view files at build time and only emits utilities it
  actually saw. After adding new utility classes to a view, run
  `DISABLE_SPRING=1 bin/rails tailwindcss:build`. The Rails dev
  server *will not* pick up new class names on its own — Sprockets
  serves the existing `tailwind.css` build until it's rewritten.
- **HAML class shorthand can't hold Tailwind brackets *or* decimal
  class names.** `.text-[10px]` in the dotted-shorthand fails to parse
  (HAML thinks `[` opens an attribute), and `.h-1\.5` doesn't work
  either — `\.` is not a valid escape; HAML eats `h-1` as one class
  and dumps the rest of the line as text content. Any utility with
  brackets (`text-[10px]`, `grid-cols-[12px_minmax(0,2.4fr)]`) or
  decimal names (`h-1.5`, `w-2.5`, `gap-0.5`) must live in the
  explicit `{ class: "…" }` hash. Same goes for empty tags — write
  `%span &nbsp;` or give the tag content; bare `%span` followed by
  sibling tags trips an "illegal nesting" error.
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
- **Submission destroy refreshes TCC + Commit scalars in a specific
  order.** `Submission` carries `before_destroy
  :remember_affected_tcc_ids, prepend: true` (the `prepend` is
  load-bearing — without it the capture fires AFTER the
  `dependent: :destroy` cascade and the through-association is
  already empty). `after_commit :update_commit` then refreshes
  the captured TCCs first, then `commit.update_scalars` — order
  matters since the commit's counts read TCC statuses. Don't
  re-add `dependent: :destroy` to associations under Submission
  without thinking about whether the capture needs extending.
  And don't write `self.status ||= :untested` in any
  scalar-recompute method — `||=` won't reset a previously-set
  status; use `self.status = :untested` then override based on
  outcomes.
- **User destroy cascades all the way down.** `User has_many
  :computers, dependent: :destroy`, which chains through
  computers → submissions → test_instances → instance_inlists →
  inlist_data. Belt-and-suspenders: `computers.user_id` carries a
  real FK with `ON DELETE CASCADE`, so even a callback-bypassing
  `User.where(id: X).delete_all` keeps the table consistent. The
  Submission scalar-refresh cascade above fires once per
  destroyed submission during this walk, so a heavy user can
  produce thousands of after_commit invocations — slow but
  correct. See [`spec/models/user_destroy_cascade_spec.rb`](spec/models/user_destroy_cascade_spec.rb).

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
