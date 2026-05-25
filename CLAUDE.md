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
  the `frontend-tailwind` branch. **Steps 0–7 are landed**, plus
  Step 8's first wing-it page — `test_cases#show` (test history
  across commits) — Tailwind + Turbo + Stimulus + importmap are
  installed alongside the legacy stack; the 404 page, login, the
  commits index (`/:branch/commits`), the commit detail page
  (`/:branch/commits/:sha`), the test-on-commit page
  (`/:branch/commits/:sha/test_cases/:module/:test_case`), the
  test-case history page
  (`/:branch/test_cases/:module/:test_case`), and the
  computers list + detail pages (`/users/:id/computers`,
  `/users/:id/computers/:id`, `/all_computers`), and the
  users list + detail pages (`/users`, `/users/:id`) all render
  through the modern layout.
  Commit detail has four tabs (Summary / Computers / Diff vs
  last pass / Build logs) — the original Tests tab was folded
  into Summary when review flagged it as redundant with the
  matrix. The merged Summary panel hosts a chip + module
  dropdown + free-text-search toolbar over the full Tests ×
  Computers matrix (sealed sticky band with right-aligned
  legend; horizontal scroll on narrow viewports synced via
  JS), and clicking any cell opens a popover with that
  (test, computer)'s failure mode, checksum grouping, SDK,
  runtime, and submission count, rendered from a JSON blob
  embedded in the page (no per-click database query). Clean
  cells get a minimal stub popover instead of navigating away,
  so click behavior is consistent. On `xl+` the popover renders
  into a docked right rail (sticky, with per-computer mini
  summary as its inactive state); below xl it falls back to a
  floating panel anchored to the clicked cell. Computers cards carry a maintainer link,
  SDK chip, probe-gated log links, and a last-successful-build
  link on no-build cards. Diff vs last pass uses the matrix
  cell encoding (before / after drawings) with a grouped
  change-counts summary line. The Logs tab proxies upstream
  build logs server-side with an availability probe.
  Aggregation helpers in
  [`app/models/concerns/commit_state.rb`](app/models/concerns/commit_state.rb)
  cover `#commit_state` / `#test_computer_matrix` (memoized
  per-instance) / `#per_computer_summary` (includes per-computer
  submissions) / `#per_test_summary` / `#cells_changed_since` /
  `#default_detail_tab` / `#last_successful_build_commit_for` /
  `#cell_popover_data`; Branch helpers in
  [`app/models/branch.rb`](app/models/branch.rb) add
  `#sparkline_data` / `#commit_neighbors` /
  `#focused_commit_window` / `#last_clean_commit_before`;
  `TestCaseCommit#instances_for_display` round out the layer.
  Matrix cell visuals come from the `matrix_cell_visual` helper
  in [`CommitsHelper`](app/helpers/commits_helper.rb) — same SVG
  output as the original partial, but called as a plain helper to
  avoid the per-cell partial-render overhead (the History tab on
  test_cases#show can paint 700+ cells per request). Stimulus controllers driving the page:
  `tabs_controller.js`, `matrix_filter_controller.js`,
  `matrix_scroll_controller.js` (header↔body horizontal scroll
  sync), `popover_controller.js`, `dropdown_controller.js`,
  `logs_controller.js`, `computer_card_controller.js`,
  `subway_map_controller.js`, `pan_map_controller.js`,
  `calendar_controller.js`, `theme_controller.js`,
  `copy_button_controller.js`. The test-on-commit page
  (`test_case_commits#show`, Step 7) has two tabs: Summary
  (default, the 19-column instances table with grouped
  column picker + status-segment + free-text filters +
  icons legend) and Logs (proxied `out.txt` / `mk.txt` /
  `err.txt` viewer with computer + type pickers). The
  column picker's preset map lives in
  [`TestCaseCommitsHelper`](app/helpers/test_case_commits_helper.rb)
  and the active set persists to
  `localStorage["mesa.test_on_commit.columns.v1"]`. The
  Logs tab calls `test_case_commits#log` to proxy a single
  file (friendly per-type 404 messages naming the file and
  pointing at sibling types) and `#log_status` to HEAD-probe
  all three types per (commit, computer, test) in one round
  trip (10-minute server-side cache, shared with the per-
  row "logs ↗" jump link's reveal probe). The proxy
  machinery (`fetch_log`, `probe_log_url`, the
  `LogNotFound` / `LogTooLarge` / `LogFetchError` error
  types, 5 MB byte cap, open/read timeouts) lives in the
  [`LogProxy`](app/controllers/concerns/log_proxy.rb)
  concern included by both `TestCaseCommitsController` and
  `CommitsController`. The headline card has two tiers:
  full-width status sentence on top — the test pill is a
  picker dropdown listing every TCC on this commit, sorted
  worst-first by status, then by module (star → binary →
  astero per `TestCase.modules`), then alphabetically by
  name — and below it a `lg:grid-cols-2` split with commit
  identity (message + expander + author + time + GitHub
  button top-right) on the left and a test-history capsule
  (single-color subway map centered + Full history button
  top-right) on the right. Subway stations link to that
  commit's test-on-commit page and reveal popovers (SHA ·
  age · message · author · this test's status) via the
  shared `subway_map_controller.js`. The test-case history page
  (`test_cases#show`) shares the headline + tab-strip frame from
  the test-on-commit page but adds a shared time-window toolbar
  (anchor commit picker with SHA-paste + date-snap-to-nearest +
  jump-to-HEAD shortcut, window size 25/50/100/250, ← Newer /
  Older → pan by half-window) that drives all three tabs:
  **History** (default — per-commit rows with status pills + a
  per-row computer ribbon that reuses the matrix cell encoding +
  popover with degradation metrics like steps/retries/log E err
  on a docked rail at xl+), **Trend** (uPlot line chart of a
  chosen metric vs commit *index* — equally spaced — for the
  top-3 most-common `(computer, threads, run_optional)` config
  tuples with a status strip drawn at the bottom of the plot
  area and a brand-colored vertical anchor marker; click any
  point re-centers the toolbar), and **Submissions** (per-
  instance table for a chosen computer over the window — picker
  auto-selects the most-active in the window). The toolbar's
  URL params (`?tab=&center=&window=&metric=&computer=`) all
  round-trip via the `toolbar_path` helper so pan / tab switch /
  metric change preserve everything else.

  `TestCase#commit_window` and `#trend_payload` plus the
  TestCasesHelper's `submissions_payload` /
  `history_popover_data` / `history_matrix_payload` build all
  per-tab data off ONE eagerly-loaded TCC scope
  (`test_instances: [:computer, { instance_inlists: :inlist_data }]`)
  so a 100-commit window completes in ~25 queries.

  Stimulus controllers added for this page:
  `trend_chart_controller.js` (uPlot wrapper that lives inside
  initially-hidden tab panels — uses a MutationObserver on the
  panel's `hidden` attribute to `setSize` once visible, since
  uPlot bakes width at construction time).

  The `computers#index` + `#show` pair (Step 8g–8h) shares the
  breadcrumb + status-sentence headline + sticky-thead table
  vocabulary used by the test-case pages. Show adds a
  hairline-split lower tier with Hardware (Platform / Processor /
  RAM) on the left and Usage (CPU hours over 24h / year / all
  time) on the right. Same Build status pill (Built / Failed /
  Not reported) as the commit-show banners. The admin
  `/all_computers` view threads through the same `index` template
  with an extra Maintainer column. Index supports a Sort dropdown
  (Most recent activity / Maintainer (A→Z) / Computer name (A→Z))
  backed by a `Computer.ordered(sort)` scope — the "recent"
  branch uses a correlated subquery against `submissions(MAX
  created_at)`, with a composite
  `submissions(computer_id, created_at)` index added to keep
  the query under 5ms on the prod-sized submissions table.

  computers#show also hosts a self-serve bulk-delete flow for
  submissions (so a maintainer can clean up a bad batch from a
  misconfigured SDK without escalating to the admin). Three
  layers wire together:
  - **Filter toolbar** on the submissions card:
    `?from=&to=&sha=` URL params, parsed by
    `Submission.submitted_between` + `Submission.for_commit_sha`
    (4-char minimum case-insensitive prefix). Header switches
    to "N submissions matching the filter" when active.
  - **Selection UI** powered by
    `submission_selection_controller.js`: per-row checkboxes
    (only rendered for `self_or_admin?`), a "select all on
    this page" header checkbox with indeterminate tri-state, a
    sticky brand-soft selection bar, and a
    "Select all M matching the filter" link that appears when
    the filter scope exceeds the visible page AND every
    visible row is ticked — flips the form into
    `select_all_matching=1` mode so the server re-derives the
    set from the filter scope.
  - **Confirmation modal** as an HTML5 `<dialog>` (centered +
    scrim backdrop styled in the modern Tailwind layer).
    Confirm POSTs to `DELETE
    /users/:user_id/computers/:id/submissions` →
    `ComputersController#destroy_submissions`, protected by
    the existing `authorize_self_or_admin` filter, scoped at
    `@computer.submissions` to prevent IDOR, and capped at
    `BULK_DESTROY_LIMIT = 500` so a single request doesn't
    spin on the `Submission#after_commit :update_commit`
    callback chain. The post-delete redirect round-trips the
    active filter params so the user lands on the same view.
    Cascade is fully audited — the destroy fires
    `before_destroy :remember_affected_tcc_ids, prepend: true`
    so the affected `TestCaseCommit` IDs are captured before
    `dependent: :destroy` wipes the `test_instances`, then
    `update_commit` refreshes the captured TCCs (resetting
    them to `:untested` when their last submission goes away)
    AND the parent `Commit` scalars, in that order. See the
    Reality-checks note + the regression specs in
    `spec/models/submission_destroy_cascade_spec.rb`.

  Pagination on the modern pages uses a new Kaminari theme at
  [`app/views/kaminari/modern/`](app/views/kaminari/modern/) —
  brand-fill for the active page, neutral mesa-btn-styled
  Older/Newer arrows. Pages opt in with
  `paginate @scope, theme: "modern"`. The Bootstrap-era partials
  at `app/views/kaminari/` keep serving un-migrated pages.

  Destructive actions on modern-layout pages use
  `button_to ..., method: :delete, form: { data: { turbo_confirm: } }`
  rather than `link_to ..., method: :delete` — the modern layout
  ships only Turbo (no rails-ujs), so `data-method=delete` from
  the legacy helper is dead.

  The `users#index` + `#show` pair (Step 8i) reuses the same
  card / breadcrumb / table vocabulary. Index is single-tier
  (status sentence + admin-gated "Create user" CTA + table with
  Name / Email / Computers chips / Actions, no paginator since
  the user list is small). Show uses the two-tier headline from
  computers#show — Tier 1 is the identity sentence ("`<name>`
  maintains `N` computers" + admin chip), Tier 2 is a Profile
  dl (Email / Time zone / Role) + Activity dl (Computers count
  / Member since) split at lg+. The computers card below uses
  the same row vocabulary as `computers#index`, minus the
  Maintainer column. `UsersController#index` was bumped to
  `User.includes(:computers)` so the chip rendering doesn't
  N+1 against `users` rows.

  Step 8's remaining wing-it pages (`test_instances#*`, admin,
  users-forms) are still outstanding; the page priority list
  is at the bottom of
  [`docs/frontend-modernization.md`](docs/frontend-modernization.md).
  Note: `computers#test_instances_index` was deleted, not
  modernized — it had been dead since the SVN→git transition
  (controller ordered by the missing `mesa_version` column, view
  linked to the missing `Version` model) and nothing in the app
  pointed at the route. The orphan empty
  `users/computers_index.html.haml` template (no controller
  action, no route, no link) was also deleted alongside the
  users#index/#show modernization.

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
- **The test suite is small but real.** 255 specs (request + model +
  helper + job) cover auth, submissions API, GitHub webhook (now
  async via `BranchSyncJob`, payload-driven), branch deletion, the
  Octokit middleware wiring, `TestInstance.query`,
  `Commit#computer_info`, the Phase 3.5 ingestion + topology +
  ordering + reconcile path, the test_cases#show branch-scoped
  helpers (`#commit_window`, `#status_summary_for`,
  `#trend_payload`) + the `TestCasesHelper#submissions_payload`
  picker logic, the computers#show bulk-delete + filter +
  permissions matrix, the Submission destroy cascade scalar
  refresh, and high-traffic page renders. They are the regression
  safety net for upcoming work — build on this rather than
  starting fresh.
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
