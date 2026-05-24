# Phase 4 — Frontend modernization

This document captures the plan to retire the legacy frontend stack
(Bootstrap 4 + jQuery + Turbolinks + Sprockets-driven JS bundling) in
favor of the Rails 8 native stack (Tailwind + Turbo + Stimulus +
importmap-rails), and to port the new design captured in
[`design_handoff_mesa_testhub/`](design_handoff_mesa_testhub/) into the
app.

The phase lands on its own branch (`frontend-tailwind`) and is
expected to span multiple sessions.

## Goals

- Drop the legacy frontend stack listed below.
- Adopt Tailwind + Turbo + Stimulus + importmap-rails.
- Port the three prototyped pages (commits list, commit detail,
  test-on-commit) faithfully to the design handoff.
- Adapt all other pages to the same visual language as best we can
  without specific designs to lean on ("wing it" using the established
  tokens, components, and patterns).
- Refactor the commit status model to match the design's orthogonal
  build / tests / flags structure (it's a cleaner domain model than
  what we have now, regardless of the visual rewrite).

## Stack changes

**Out**
- `bootstrap` (4.x), `bootstrap_form`, `jquery-rails`
- `turbolinks` (replaced by Turbo)
- `sassc-rails`, `uglifier`
- Sprockets-driven JS bundling (CSS via Sprockets may stay if Tailwind
  CLI is the easier path; decide in Step 1)
- The `app/assets/javascripts/*.js` files converted from CoffeeScript
  in Phase 1.5 — most can become Stimulus controllers.

**In**
- `tailwindcss-rails` (uses Tailwind standalone CLI under the hood;
  no Node toolchain required)
- `turbo-rails` (Hotwire)
- `stimulus-rails` (Hotwire)
- `importmap-rails` (ESM via import maps; no bundler)

## Design source material

[`docs/design_handoff_mesa_testhub/`](design_handoff_mesa_testhub/)
is the authoritative visual + interaction reference. Notable artifacts:

- `README.md` — the design intent doc. Read first.
- `styles/tokens.css` — design tokens (colors, radii, shadows,
  typography, spacing). Port to `tailwind.config.js`'s
  `theme.extend.*` blocks.
- `prototype/` — React + Babel-in-the-browser prototype. **Reference
  only** — do not copy the React or hash-routing approach. The
  component structure in `components.jsx` and `screens.jsx` is useful
  as a guide to what partials + Stimulus controllers to build.
- `screenshots/` — pixel-level reference renders for each major
  state. Use these as the visual acceptance check.
- `assets/mesa-mark.svg`, `assets/mesa-wordmark.svg` — the
  rebranded logo. Drop into `app/assets/images/`.

The handoff covers three pages in detail (commits list, commit
detail, test-on-commit) and ten or so demo SHAs that exercise
specific states. Pages not in the handoff get "winged" using the
established tokens and components — see "Pages without designs"
below.

## Status model refactor (do this before any view work)

The design's status model is a real improvement over the current
`Commit#status` integer:

- **Build status** (`all-ok` / `some-fail` / `all-fail`) — derived
  from per-computer compile state.
- **Tests status** (`fail` / `mixed` / `pending` / `pending-partial`
  / `all-pass` / `not-run`) — single-token, worst-first prioritized.
- **Flags** (`fpe`, `checksum`, `inlists_full`) — orthogonal signals,
  surfaced as counts/pills, **never** rolled into a "Flagged" status.

The existing `commits.status` integer conflates several of these. The
refactor:

1. Add `Commit#build_status`, `Commit#tests_status`, and
   `Commit#flag_counts` derived methods that return symbols matching
   the design's vocabulary. Each backed by the underlying
   `compilation_status`, `test_case_commits`, and
   `test_instances` data we already have.
2. Add `Commit#commit_state` returning the aggregated hash shape the
   design assumes (matching `getCommitState(sha)` in
   `prototype/data.js`).
3. Leave the `commits.status` column in place for now. The new
   methods derive from underlying data; the column becomes redundant
   but harmless. Drop in a later cleanup commit if nothing reads it.

## Aggregation helpers (the design's API surface)

The prototype implements three helpers in `data.js` that the views
treat as inputs. Implement Rails equivalents as plain Ruby methods
with specs, before any view code consumes them:

| Prototype                                  | Rails equivalent                                |
| ------------------------------------------ | ----------------------------------------------- |
| `getCommitState(sha)`                      | `Commit#commit_state`                           |
| `getMatrixForCommit(sha)`                  | `Commit#test_computer_matrix`                   |
| `getInstancesForTestOnCommit(sha, testId)` | `TestCaseCommit#instances_for_display`          |
| `recentCommitsForSparkline(branch, n=12)`  | `Branch#sparkline_data(limit: 12)`              |

The Tests×Computer matrix is the algorithmically interesting one.
The shape is `{ test_id => { computer_id => { status:, flags: {} } } }`.
It's a cross-tab over `test_case_commits` (test side) joined with
`test_instances` (computer side); spec it carefully against the demo
scenarios.

The sparkline is straightforward: take the last 12 commits via
`Branch#ordered_commits.limit(12)`, call `commit_state` on each.

## Sequencing

Each step is its own commit or small commit set on `frontend-tailwind`.
Aim for green on every commit (`bundle exec rspec` + manual smoke).

### Step 0 — Inventory and decisions

Before any code lands:

- Enumerate every view file under `app/views/` and classify each:
  - **Designed** (commits index/show, test-on-commit) — port to
    handoff
  - **Wing it** (everything else: auth, 404, computers, users,
    submissions, test_cases across commits, test_instances) —
    derive from established tokens + components
  - **Defer** (anything we decide to leave on Bootstrap for now)
- Decide: importmap-rails or jsbundling-rails? Default to importmap
  (zero build step). Jsbundling only if we discover a hard
  requirement.
- Decide: Tailwind via `tailwindcss-rails` gem (standalone CLI)
  or via the Rails 8 generator. Default to the gem.

Output: a short checklist comment in this doc enumerating the
classification.

#### Step 0 output (recorded 2026-05-20)

**Stack decisions**

- **JS loading**: `importmap-rails`. No bundler, no Node toolchain at
  runtime. Stimulus + Turbo ship as importmap pins; Tailwind compiles
  via the `tailwindcss-rails` standalone CLI which doesn't need Node
  either. The legacy `app/assets/javascripts/*.js` files keep loading
  through Sprockets in the meantime, so the two stacks are completely
  decoupled.
- **CSS**: `tailwindcss-rails` gem (standalone CLI). One generated
  bundle at `app/assets/builds/tailwind.css`, served by Sprockets the
  same way `application.css` already is. Bootstrap's compiled CSS
  stays in `application.css` until every view migrates.
- **Templating**: HAML for new partials too, matching the existing
  codebase. Tailwind classes work fine in HAML attribute hashes;
  long class lists go on the next line.
- **Coexistence strategy**: the existing
  `layouts/application.html.haml` keeps rendering legacy views via
  Bootstrap. A new `layouts/modern.html.haml` (Tailwind + Turbo +
  Stimulus + design tokens) gets opted into per-controller as we
  port pages. Once every controller flips, the legacy layout and its
  Bootstrap/jQuery/Turbolinks asset chain get deleted in Step 9.

**View classification**

Counted 88 view files under `app/views/`; the user-facing surface is
63 templates (excluding `.jbuilder`, mailer views, and Kaminari
partials). Classification below — anything not listed is implicitly
"wing it" since the design only covers three pages in detail.

*Designed (Steps 5–7, port to handoff)*

- `commits/index.html.haml` + its `_index_*` partials (commits list)
- `commits/show.html.haml` + its hero/banner/matrix/tab partials
  (commit detail; new partials replace `_badges`, `_checksums`,
  `_failures`, `_complete`, `_none_tested`, the fraction partials)
- `test_case_commits/show.html.haml` (test-on-commit, with column
  picker via Stimulus replacing the broken cookie-based version)

*Wing it (Step 4 + Step 8, derive from tokens + components)*

- Step 4 (low risk, end-to-end smoke):
  - `errors/not_found.html.haml`
  - `sessions/new.html.haml` (login)
  - `layouts/application.html.haml` shell + `_navigation*` partials
    (new modern layout; nav drops top-bar branch dropdown in favor of
    the inline branch chip pattern)
- Step 8, in priority order:
  - ~~`test_cases/show.html.haml` (test-across-commits)~~ — landed
    (Steps 8a–8f; History + Trend + Submissions tabs over a shared
    anchor+window toolbar; see the "Step 8" / "Pages without
    designs" sections below for the design notes).
  - ~~`computers/index.html.haml`, `computers/show.html.haml`~~ —
    landed (Steps 8g–8h; breadcrumb + status-sentence headline +
    sticky-thead table pattern, with a new "modern" Kaminari
    paginator theme that subsequent wing-it pages can opt into via
    `paginate @scope, theme: "modern"`). See "computers#index +
    computers#show design notes" below.
  - ~~`computers/test_instances_index.html.haml`~~ — **deleted**
    rather than modernized. The page was broken on `master`
    (controller ordered by the long-gone `mesa_version` column,
    view linked to the long-gone `Version` model via
    `version_path` / `test_case_version_path`), the route was
    never linked from anywhere in the app, and the use cases it
    nominally served — "all submissions from a computer with
    filter" and "all instances of one test on one computer over
    time" — are already covered by the modern `computers#show`
    submissions table and `test_cases#show` Submissions tab.
    Removed in the same commit that landed this note: the
    route, the `test_instances_index` action, the entries in
    `set_user` / `set_computer` filters, and the view template.
  - `users/index.html.haml`, `users/show.html.haml`,
    `users/admin.html.haml`, `users/computers_index.html.haml`
  - `users/new.html.haml`, `users/edit.html.haml` (signup / edit)
  - `computers/new.html.haml`, `computers/edit.html.haml`,
    `computers/_form.html.haml`
  - `test_instances/index.html.haml`, `test_instances/search.html.haml`,
    `test_instances/show.html.haml`, and `_table`/`_search_table`
    partials
  - `submissions/show.html.haml`
  - `visitors/index.html.haml`
  - `pages/about.html.erb`
  - `kaminari/*` paginator partials (replace Bootstrap markup with
    Tailwind utility classes)

*Defer (stays on the legacy layout for now)*

- `test_cases/new.html.haml`, `test_cases/edit.html.haml`,
  `test_cases/index.html.haml`, `test_cases/_form.html.haml`,
  `test_data/*` — admin-y CRUD that may not even be reachable in
  prod (the `test_cases` resource is commented out in
  `config/routes.rb`). Touch only if needed.
- `layouts/mailer.*` — outbound email; out of scope for this phase.
- `morning_mailer/*.erb` — same. Hardcoded URLs noted in
  `CLAUDE.md` "Quick gotchas" get fixed separately.

### Step 1 — Foundation

- Add gems: `tailwindcss-rails`, `turbo-rails`, `stimulus-rails`,
  `importmap-rails`.
- Remove gems: `bootstrap`, `bootstrap_form`, `jquery-rails`,
  `turbolinks`, `sassc-rails`, `uglifier`.
- Run installers: `bin/rails tailwindcss:install`,
  `bin/rails turbo:install`, `bin/rails stimulus:install`,
  `bin/rails importmap:install`.
- Port `styles/tokens.css` to `tailwind.config.js`'s
  `theme.extend.colors` / `boxShadow` / `borderRadius` / `fontFamily`
  blocks. Keep dark-mode overrides via Tailwind's `dark:` variant
  + `data-theme="dark"` on `<html>`.
- Add Inter and JetBrains Mono via webfont links (or self-host).
- Set up `app/javascript/controllers/` and the import map.
- Establish `app/views/layouts/application.html.haml` (or convert to
  ERB if simpler) with the nav, theme controller, and Tailwind
  classes.
- Smoke-test the new stack by replacing one tiny page — e.g., the
  404 — with a Tailwind version. This catches assetpipe / importmap
  / CSP / autoload issues early.

Suite stays green throughout. CI runs the same `bundle exec rspec`.

### Step 2 — Status model + aggregation helpers

- Implement `Commit#build_status`, `Commit#tests_status`,
  `Commit#flag_counts`, `Commit#commit_state`.
- Implement `Commit#test_computer_matrix`.
- Implement `Branch#sparkline_data(limit:)`.
- Implement `TestCaseCommit#instances_for_display`.
- Spec each against the demo scenarios from the handoff's README
  (`aa27a08` clean, `7c4e2d1` uniform failures, `b81f9a3` FPE flag,
  `e91a5c2` mixed + partial build, etc.). The mock data in
  `prototype/data.js` is the reference for what each scenario should
  produce.

No view changes in this step. Pure data layer.

### Step 3 — Shared component partials + Stimulus controllers

Build the inventory from the handoff once so every page consumes
the same primitives:

- `app/views/shared/_status_dot.html.haml` (or .erb)
- `_build_status_pill.html.haml`
- `_test_status_pill.html.haml`
- `_flag_chip.html.haml`
- `_status_matrix.html.haml`
- `_sparkline.html.haml` (SVG)
- `_branch_picker.html.haml`
- `_commit_avatar.html.haml`
- `_search_input.html.haml`
- `_segmented_control.html.haml`
- `_copy_button.html.haml`
- `_dropdown.html.haml`

Stimulus controllers in `app/javascript/controllers/`:

- `theme_controller.js` — cycles light → dark → system, persists
  to `localStorage.mesa-theme`, applies `data-theme` to `<html>`.
  Include the pre-load script in the layout `<head>` to avoid FOUC.
- `branch_picker_controller.js` — opens/closes the dropdown,
  filters branches by typing.
- `dropdown_controller.js` — generic click-to-open, click-outside
  to close.
- `copy_button_controller.js` — writes to clipboard, flashes
  "Copied" for 1.5s.
- `column_picker_controller.js` — toggles visible columns on the
  test-on-commit table, persists to localStorage. **Replaces** the
  currently-broken cookie-based version on `test_case_commits#show`
  (Phase 1.5 bug).
- `segmented_control_controller.js` — filter chip behavior.

Test these at least manually (and ideally via system specs for the
critical interactions — theme persistence, branch picking).

### Step 4 — Auth flow + 404 page

Low risk, low data complexity. These establish the Tailwind setup
end-to-end and let us discover layout / nav / Stimulus wiring issues
in isolation. No design reference — derive from tokens + the nav
established in Step 1.

- Login (`sessions#new`)
- Logout flow
- 404 page
- Maybe: password reset if it exists

### Step 5 — Commits list (`/:branch/commits`)

The first "designed" page. Reference:
`screenshots/01-prototype.png` (light) and `02-prototype.png` (dark).

**Status: complete (2026-05-21)**, with these design departures from
the original handoff after several review passes with the maintainer:

- **Stat tiles dropped.** Page-scope counts (Clean / Failing /
  Mixed / Build issues) didn't earn their pixel budget — a user
  scanning 25 commits already has the answer from the rows
  themselves. Removed; the reclaimed real estate now belongs to
  the subway map.
- **Sparkline replaced by an inline "subway map."** Newest-on-left
  horizontal row of one station per commit (up to 25 per page,
  13 visible at a time). Inner core dot = build status, outer
  ring = worst-of test status, transparent gap between them so
  the ring reads as a true annulus. Connecting line with a right-
  pointing arrowhead. Hovering a station reveals an HTML popover
  with message, author, age, build/tests pills; the popover
  positions itself with a percentage-based `translateX` so it
  never overflows the panel edge.
- **Two-state animated pan with auto-paginate at the edges.** A
  Stimulus controller (`pan_map_controller.js`) toggles the inner
  track between two resting positions — newest 13 (`shift = 0`)
  and oldest 13 (`shift = -(track_w - window_w)`) — using a CSS
  `transition` with `cubic-bezier(0.65, 0, 0.35, 1)` for symmetric
  ease-in-out. When the user clicks a pan button while already at
  that side's resting position, the click falls through to the
  older/newer page URL instead. Buttons reveal a "Newer" / "Older"
  text label only in this paginate-fall-through mode — chevron
  alone when they would pan, label + chevron when they would
  navigate.
- **Kaminari dropped for this index.** Replaced with cursor
  pagination keyed off `commit_time`, driven by two symmetric URL
  parameters:
    - `?before=X` — show the newest 25 commits with `commit_time
      < X`, map initializes at the newest view.
    - `?after=Y` — show the oldest 25 commits with `commit_time
      > Y` (then reversed for newest-first display), map
      initializes at the **oldest** view — i.e., the bridge
      between this page and the older one the user came from.
  Calendar date picks always emit `?before=`. The "Newer" pan
  button when paginating emits `?after=<newest visible>` so the
  user lands on the page-just-newer initialized at its oldest
  view, with the bridge commits visible — fixes the "skip 12
  commits between pages" UX bug. The headline + date chip uniformly
  show "on or before `<newest visible commit time>`" regardless
  of which URL param produced the page, so `?after=` is a
  navigation detail, not a different mental model.
- **Date picker chip in the headline.** Matches the branch-picker
  pattern: monospaced pill that opens a calendar dropdown. Picking
  a date sets `?before=YYYY-MM-DD`; the controller parses bare
  dates as end-of-day in the request's time zone (and bare-date
  `?after=` as beginning-of-day) so picked days are inclusive at
  both ends. The headline reads "Commits on `<branch>` on or
  before `<date>` _<time>_" where the muted time component
  reflects the precise cursor.
- **Cursor-relative time everywhere.** `short_relative_time` (in
  `commits_helper.rb`) returns `−6d` / `−2w` / `−3mo` (with U+2212
  minus sign) instead of "X ago," which would mislead when the
  cursor is in the past.
- **Age bucket headers re-worded to read cursor-relative.** "Today"
  → "Same day", "Yesterday" → "Day before", "Last week" → "Week
  before", etc., so the table reads coherently with the cursor
  pointing at an arbitrary date.
- **Blue/gray semantics inverted.** Blue is now "Incomplete"
  (`:pending_partial` — some passed, some untested); gray is
  "Untested" (both `:pending` and `:not_run`). The "Running"
  label is gone — the codebase doesn't actually model a "promised
  but not submitted" state.
- **Tokens brightened.** `--color-success`, `--color-warning`,
  `--color-buildfail`, `--color-danger`, `--color-info` all moved
  up the saturation scale from the GitHub Primer-style defaults.
  Soft variants stayed accessible-on-white for pill backgrounds.
- **Upper pagination + search row removed.** The pan buttons fully
  cover page navigation now; the bottom Newer/Older link pair
  remains as an anchor after scrolling. The search input is hidden
  (clearly commented) until it's wired to client-side filtering.
- **Filter chips deferred.** All / Failing / Mixed / Build issue /
  Running / Clean did not land — without the stat tiles to anchor
  them they read as noise. A Stimulus-over-table client-side
  filter could come back in a follow-up.

Components / Stimulus controllers added across Step 5's substeps:
- `app/views/commits/_branch_picker.html.haml`
- `app/views/commits/_date_picker.html.haml`
- `app/views/commits/_subway_map.html.haml` and
  `_subway_legend_swatch.html.haml`
- `app/javascript/controllers/dropdown_controller.js`
- `app/javascript/controllers/calendar_controller.js`
- `app/javascript/controllers/subway_map_controller.js` (hover popovers)
- `app/javascript/controllers/pan_map_controller.js`
- `app/helpers/commits_helper.rb` (icons, status pills, dot,
  avatar, age bucketing, cursor-relative time)

Verification: all nine demo scenarios from the handoff render
correctly against real production data restored from the prod
snapshot. Date picker + Older/Newer round-trip with the bridge-
commit semantics. Dark mode toggle persists across navigations.

#### Step 5 known followups (not blocking)

- **"Continuous pan" virtual scrolling.** The two-state pan is a
  good compromise, but the user noted that truly-continuous
  navigation (pan smoothly through the loaded commits, eagerly
  load adjacent batches via Turbo Stream / JSON, animate the
  table alongside the map) would be the ideal. Deferred — likely
  a Phase 4.5 effort once the rest of the pages are migrated.
  When that happens, the `?before=` / `?after=` URL semantics
  become an implementation detail of the page's "anchor point"
  and the in-page navigation can override it without changing
  the URL on every pan.
- **Subway map reuse on the commit detail page.** The same
  `_subway_map` partial gets one extra local — `focused_sha:` —
  in Step 6, with the focused station getting the brand-color
  outline ring (per `Sparkline`'s `current` handling at
  `components.jsx:165-168`) and a slightly larger radius. Init
  view becomes `:focused` (center the focused commit) alongside
  `:newest` / `:oldest`. Replaces the existing "nearby commits"
  dropdown.
- **Restore search bar.** Comment-marked placeholder in
  `index.html.haml` shows where to drop it back in.

### Step 6 — Commit detail (`/:branch/commits/:sha`)

The biggest page. Reference: `03-` through `08-prototype.png`.

**Status: landed (2026-05-22)**. Scaffolding (2026-05-21) established
structure, helpers, and skeleton tabs; subsequent passes filled
out the matrix, the in-page log proxy + lazy load + availability
probe, the per-segment subway-map arrows, the soft-color banner
fills with cross-panel filter handoffs, the test-classification
rule that calls "pass + pending neighbors" passing (not pending),
and the four substep follow-ups (Tests-tab search + ribbon,
Computers-card polish, Diff-tab cell visualisation, sticky matrix
header). The Tests tab itself was subsequently folded into
Summary (see "Summary/Tests merge" below) so the matrix is now
the single primary lens for test-side state.

Helpers added in advance of the view work (with specs):
- `Branch#commit_neighbors(commit)` — `{ older:, newer: }` by
  `commit_time`, drives the breadcrumb's prev/next buttons.
- `Branch#last_clean_commit_before(commit, depth: 25)` — walks
  older commits and returns the first all-built + all-passing
  one; bounded so the walk is predictable on stale branches.
- `Commit#default_detail_tab(state:)` — :computers / :tests /
  :summary, picked server-side so there's no client-side flicker.
- `Commit#per_computer_summary` — one hash per computer that
  submitted, sorted worst-first, with pass/fail/pending/fpe/
  checksum counts.
- `Commit#per_test_summary` — one hash per test case with the
  worst-first overall token and a per-computer cell row.
- `Commit#cells_changed_since(other)` — matrix-diff for the
  Diff tab; reports regressions and new fpe/checksum flags,
  excludes informational `inlists_full`.

Departures from the original handoff:
- **Tabs are toggled in-place by a Stimulus controller** rather
  than via Turbo Frames. All five panels render on the initial
  request and the `tabs_controller.js` swaps `hidden` on click,
  also updating `?tab=<id>` via `history.replaceState` so the
  URL stays bookmarkable. The show page also opts out of Turbo
  Drive's snapshot cache via
  `<meta name="turbo-cache-control" content="no-cache">`; the
  `replaceState` desyncs Turbo's URL tracking enough that
  browser-back from the index would otherwise leave URL and body
  out of sync.
- **Cross-panel handoffs use a single `tabs:request` event.**
  `switchFromLink` parses every non-`tab` URL param off the
  clicked link's href into `detail.params` and dispatches; panel
  controllers (filter chips, logs picker) decode whichever keys
  they care about. Banner "See failing tests" packs
  `?tab=summary&filter=failing`; a Computers-tab failed-build
  card packs `?tab=logs&computer=rusty`. The same URL works as a
  direct deep link, and legacy `?tab=tests` URLs route to
  Summary in the controller so old bookmarks keep working.
- **`Diff vs last pass` lookback is capped at 25 older commits.**
  The walk's per-commit cost is "build a matrix" which is itself
  a couple of queries, so an unbounded walk on a stale branch
  could easily fan out. If nothing turns up the tab is disabled
  rather than slow.
- **"Files changed" line in the hero meta is dropped** because
  the codebase has no `files_changed` column — the prototype's
  number came from a mock. PR number is parsed from the commit
  message's trailing `(#NNN)`. The hero shows a `<details>`
  disclosure for any commit-message body so multi-paragraph
  PR-merge descriptions stay accessible without dominating the
  hero.
- **Logs tab is embedded via a server-side proxy** at
  `GET /:branch/commits/:sha/build_log/:computer` (5 MB cap,
  short timeouts, validates the computer actually submitted to
  the commit). A sibling `build_log_status/:computer` does a
  HEAD probe — cached for 10 minutes — so the Logs tab can
  disable itself with a tooltip when no upstream log exists.
  The picker is a row of state-dot-prefixed mono buttons plus
  a `download` link in the corner.
- **Subway map: per-segment arrowheads + 5-station focused
  variant.** The index and hero subway maps both drop their
  end-cap arrowhead in favor of one small left-pointing triangle
  per segment between stations. The hero's `_hero_subway_map`
  partial centers a 5-station window on the focused commit,
  enlarging that station and ringing it in the brand color;
  popovers reuse the index page's `subway-map` controller.
- **Banner cards use a soft-tone fill instead of a left accent.**
  All five (`build_fail`, `build_partial`, `failing`, `mixed`,
  `pending`) use `var(--color-X-soft)` + `var(--color-X)`
  border + `var(--color-X-soft-text)` text. The Failing banner's
  last-passing-commit SHA is an underlined inline link
  inheriting the danger color rather than a clashing brand-blue
  pill. The "Pending" banner uses the literal word "pending"
  because we don't know whether non-reporting tests are actually
  running.
- **Test classification.** A test counts as "passing" if any
  computer ran it and reported a pass, AND nothing failed, AND
  nothing reported a checksum mismatch. Pending neighbors don't
  downgrade — the Summary matrix's chip filter still surfaces
  those rows so the user can see *which* computers haven't
  reported, but the hero stats and Summary chip filters treat
  them as passing. `:pending` only fires when no computer has
  reported a pass at all.

Substep follow-ups landed 2026-05-22:
- **Tests tab:** the `tests-filter` Stimulus controller now layers
  three AND-wise filters — chip (status/flag category), module
  dropdown (star / binary / astero), and free-text search across
  test names. Modules with zero rows on the current commit are
  dropped from the dropdown; the dropdown itself is suppressed
  when only a single module is present. Each row is now an `<a>`
  to the test-on-commit page, and the trailing "1 fail · 105 pass"
  text is replaced by a row of 14-px mini matrix cells — one per
  computer, in the same worst-first order as the Summary matrix
  columns. The summary text moves into the row's
  `aria-label`/`title` so screen-reader + hover users still get
  the digest.
- **Computers tab:** cards now carry a "maintained by <user>"
  line linking to the user page, a mono SDK/compiler chip
  (sourced from `Submission#computer_specification` and
  deduplicated across this commit's submissions), an OS pill, a
  "Last successful build: <sha>" link on no-build cards (backed
  by the new `Commit#last_successful_build_commit_for(computer)`
  query — single LIMIT 1 against the indexed submissions table),
  and a probe-gated log link. A new
  `computer_card_controller.js` Stimulus controller fires
  `GET /:branch/commits/:sha/build_log_status/:computer` on
  connect and hides the "logs ↗" / "build logs ↗" link in favor
  of a muted "no log uploaded" placeholder when the upstream
  probe says nothing's there (10-minute server-side cache shared
  with the Logs tab's own probe).
- **Diff tab:** the "pass → fail" / "FPE raised" text was
  replaced with two 18-px matrix-cell drawings (before / after)
  separated by an arrow icon, matching the cell encoding used on
  the Summary matrix and the new Tests-tab ribbon. A summary
  line at the top of the panel reads
  "N new failures · M new FPE flags · K new checksum mismatches"
  (only the non-zero parts are joined). Each row is also an
  `<a>` to the affected test-on-commit page.
- **Sticky matrix header:** the rotated computer-name header row
  in `_matrix.html.haml` now uses `position: sticky; top: 0;`
  with a `bg-bg-elev` background and `z-index: 10`. The wrapping
  `overflow-x-auto` was removed because it promotes overflow-y
  to `auto` and traps sticky positioning inside the wrapper; on
  the rare commit wide enough to overflow the panel column, the
  document itself scrolls horizontally instead. Matrix cell
  visuals are produced by the `matrix_cell_visual` helper
  (originally a `_matrix_cell_visual.html.haml` partial; promoted
  to a helper when the test_cases#show History tab started
  painting 700+ cells per request and the per-partial overhead
  showed up in the dev log). The encoding helper
  (`matrix_cell_attrs`) is still the single source of truth for
  colors / glyphs / corner badges.

Summary/Tests merge landed 2026-05-22:

The Tests tab was doing nearly the same job as the Summary matrix
at a coarser granularity — same data, same chips, just aggregated
by test row instead of cell. Maintainer review flagged it as
redundant, and the per-row "ribbon" added on the Tests tab to
show per-computer status was effectively a slimmer matrix. The
merge turns Summary into the single primary lens.

- **One tab, three filter axes.** The chip / module dropdown /
  search toolbar that briefly lived on the Tests tab moved onto
  the matrix panel itself. The Stimulus controller was renamed
  `tests-filter` → `matrix-filter`. All rows render (not just
  "interesting" ones); the controller hides them via `hidden`
  on a `display: contents` row wrapper, which removes the
  wrapped grid items from layout cleanly without breaking the
  column alignment.
- **Worst-first default chip.** `default_matrix_filter(per_test)`
  picks `failing` → `mixed` → `pending` → `checksums` → `fpe` →
  `all`, mirroring the worst-first logic of
  `default_detail_tab`. On a clean commit the chip lands on
  "All" so the user sees the wall of green as confirmation
  rather than an empty filter result.
- **Cell-aware pending.** `test_row_categories` now adds
  `"pending"` to any row carrying pending cells, even when the
  row's overall state is `:fail` or `:mixed`. Clicking the
  "Pending" chip surfaces every still-in-flight situation, not
  just rows where everything is pending.
- **Cell click → popover.** Cells became `<button>` triggers
  (`_matrix_cell_trigger.html.haml`) that open an in-page
  popover with the cell's failure mode, summary text snippet,
  checksum + grouping note, SDK, runtime, and submission count.
  The popover has both a header X button and a footer
  "Close" / "Clear selection" text button — two ways to dismiss
  for touch and keyboard users. Hover-grow (`scale-125`,
  cursor-zoom-in) is preserved only for "interesting" cells so
  the affordance still communicates which cells carry rich
  content; clean cells stay calm on hover. Cell triggers carry
  `touch-action: manipulation` to skip the 300ms double-tap
  delay on mobile. Floating popover positioning is dynamic —
  flips to the cell's left if it'd overflow right of viewport,
  clamps top to stay in view.
- **Embedded popover JSON.** `Commit#cell_popover_data` builds a
  hash keyed by `"#{test_id}-#{computer_id}"` covering every
  cell. The "interesting" cells (anything non-clean-pass) carry
  the full payload: `failure_type` (humanized via
  `TestInstance.failure_types`), `summary_text` snippet,
  `checksum`, `sdk_version`, `runtime_minutes`,
  `submission_count`, `agreement` (`:single` / `:unanimous` /
  `:pass_fail_mixed` / `:checksum_mixed`), and for
  checksum-flagged cells `checksum_match_count` /
  `checksum_match_total` from `_checksum_sibling_counts`. Clean
  cells get a minimal stub (test/computer/PASS/SDK/runtime/link)
  so click behavior is consistent — every cell opens a popover,
  no surprise navigation. The hash is rendered into a single
  `<script type="application/json">` block at the bottom of the
  matrix; the popover controller parses it once on connect and
  caches the resulting map. No per-popover database query.
- **Memoized matrix.** Before this work the controller called
  `commit_state`, `test_computer_matrix`, `per_computer_summary`,
  `per_test_summary`, and `cell_popover_data` — each of which
  triggered `_build_test_computer_matrix` from scratch. The
  matrix is now memoized on the `Commit` instance via
  `@_test_computer_matrix`, dropped when the request ends. Same
  applies to the eager-loaded `_tccs_for_matrix` array.
- **Tab strip dropped the Tests entry.** Four tabs now
  (Summary / Computers / Diff vs last pass / Build logs).
  `default_detail_tab` no longer returns `:tests`; build trouble
  still routes to Computers, everything else to Summary.
  The Computers sidebar that used to flank the Summary matrix
  was dropped — per-computer detail lives on the Computers tab
  with more depth, and the matrix's column headers already give
  a worst-first scan of which computers are in trouble.
- **Banner deep-links updated.** "See failing tests" /
  "See mixed tests" buttons now emit `?tab=summary&filter=…`
  instead of `?tab=tests&…`. Legacy `?tab=tests` URLs route to
  Summary in the controller, preserving any `?filter=` param
  so existing bookmarks keep working.
- **Test name in row label is a link.** The
  `module/test_name` column on the left of each matrix row
  links to the test-on-commit page (no computer filter). The
  popover footer link is the per-(test, computer) link.

Matrix layout refinements (also 2026-05-22 / 23):

- **Sealed sticky header band.** The rotated column-name header
  and the legend live in one solid `position: sticky; top: 0;
  z-20; bg-bg-elev` block *outside* the body grid. That seals
  the 4px gaps between header cells and the corner badges that
  used to peek through (`top: -2px` on `:inlists_full` plus
  pucks). The header band uses `overflow-x: clip` rather than
  `auto/hidden` so it doesn't establish a scroll container —
  which would trap vertical sticky inside the band — and its
  inner row gets `width: max-content` so the column headers can
  exceed the band's visible width and be translated horizontally
  to follow body scroll.
- **Legend right-aligned to the matrix's right edge.** The
  legend container's `max-width` is pinned to the matrix's
  natural width (`240 + 26 × N` where N = computers), keeping
  the legend's right edge flush with the rightmost column
  header rather than floating off in the panel's empty right
  region.
- **Horizontal scroll, vertical sticky preserved.** The body
  grid sits in a `overflow-x: auto` wrapper so on narrow
  viewports the matrix scrolls within the panel instead of
  pushing the document into horizontal scroll.
  `matrix_scroll_controller.js` listens for the body's `scroll`
  event and applies `transform: translateX(-scrollLeft)` to the
  sticky band's inner header row, keeping column headers
  aligned with the cells visible below. The sticky band stays
  outside the scroll container so its vertical sticky still
  pins to the viewport.

Docked detail rail (Step 6 polish, 2026-05-23):

The right portion of the Summary panel was empty whitespace on
wide screens. A docked rail now absorbs it and turns it into
useful surface for the popover.

- **`xl:flex` layout.** `_tab_summary.html.haml` wraps the
  matrix + rail in a flex container that splits matrix-on-left,
  rail-on-right at `xl+` (1280px). Below xl, the rail
  (`.hidden.xl:block.xl:w-80.xl:shrink-0`) collapses out and
  the matrix gets full width. The `popover` Stimulus controller
  lives on this wrapper (not on the matrix panel) so its
  `dockedContent` target sits inside its scope alongside the
  matrix cell triggers. `matrix-filter` + `matrix-scroll` stay
  on the matrix panel where their targets live.
- **Sticky rail, no `items-start`.** The flex wrapper uses
  default `items-stretch` so the rail column grows to match the
  matrix column's height. That gives the sticky inner panel
  (`position: sticky; top: 16px`) room to track against — with
  `items-start` the rail column sat at its content height and
  sticky had nothing to pin to, so it scrolled off-screen on
  tall matrices.
- **Inactive vs active state.** `_matrix_rail_inactive` (per-
  computer mini summary with worst-first dot + name + status
  text + a "Click any matrix cell" hint) renders server-side
  into the rail. The popover controller stashes this HTML in
  `connect()` and restores it on `close()`. When a cell is
  clicked, the same JS that builds the floating popover content
  swaps the rail's `innerHTML`. Clicks on other cells just
  re-render the rail (no jumping popover); clicks outside the
  rail are ignored in docked mode to avoid wiping a selection
  the user is still reading.
- **Routing rule.** `popover#open` checks
  `dockedContentTarget.offsetParent` — non-null at `xl+` (rail
  visible), null below (rail collapsed). When docked, content
  goes to the rail and the floating panel is left hidden; the
  X / footer-button label switches from "Close" to "Clear
  selection" to match the rail's "stays visible after clear"
  mental model.

### Step 6 known followups (not blocking)

- **Header nav overflow on narrow viewports.** ~~Pre-existing
  issue in `layouts/modern.html.haml` — the top navigation bar
  doesn't collapse gracefully below ~640px and pushes the
  document into horizontal scroll even when the page body
  itself fits.~~ Resolved: the inline nav now collapses to a
  hamburger + slide-down panel below 880px (the lowest width
  where the four nav links + Admin + theme + user + Log out
  fit on a single line). The hamburger reuses
  `dropdown_controller`, which was extended to sync
  `aria-expanded` on an optional `trigger` target. The three
  existing dropdowns (branch picker, date picker, matrix
  module dropdown) were retrofitted to use that target, so
  their `aria-expanded` now reflects open state for assistive
  tech instead of being stuck at `"false"`.

### Step 7 — Test on commit (`/:branch/commits/:sha/test_cases/:module/:test_case`)

Reference: `09-`, `10-`, `11-prototype.png`.

**Status: landed (2026-05-23)** on `frontend-tailwind`. The page
now renders through `layouts/modern.html.haml`; the legacy
Bootstrap markup at `test_case_commits/show.html.haml` is gone,
replaced by a small skeleton that composes a stack of new
partials. The page picked up a Summary / Logs tab strip during
this round (the file list at the bottom of this section
reflects the final shape, not the initial port).

Departures from the original handoff:

- **Color-coded headline word + checksum word.** The
  `_headline.html.haml` partial composes the sentence
  ```
  <test> (<module>) is <status> in <sha> with <N> unique checksum(s).
  ```
  with status/word colors derived from the test_instance pass/fail
  mix, and `one|two|three|N` for the checksum count. Multi-checksum
  rows get the "Bit-for-bit reproducibility broken on this commit.
  Checksums seen: …" sub-line. The status helper is
  `TestCaseCommitsHelper#headline_status` and lives next to the
  column catalog.
- **Variant column dropped entirely.** The prototype's `out/mk`
  shorthand mapped to log-file types; an initial port translated
  it to a schema-flag concatenation (`photo+full+fpe+fine`), but
  every value it could produce is already encoded in the
  status-cell icons (wrench for FPE, ≠ for checksum divergence,
  + for full inlists) and the success_type portion of the status
  label ("PASS: Photo checksum"). Keeping the column was pure
  visual duplication and pushed the default set past a
  one-screen-wide layout. The catalog is now 19 columns instead
  of 20.
- **HTML table, not CSS grid.** The instances table is a native
  `<table>` with sticky header. Each `<th>` and `<td>` carries
  `data-col="<id>"`; the `column-picker` Stimulus controller
  toggles `hidden` on cells whose id isn't in the active set,
  which collapses the column from the table layout entirely
  (sibling cells reflow into the freed width). Cleaner than the
  prototype's grid + `display: contents` rows when there are 20
  toggleable columns and per-column widths to maintain.
- **Nineteen columns grouped Run / Output / Convergence.**
  Column catalog lives in
  [`TestCaseCommitsHelper::INSTANCE_COLUMNS`](app/helpers/test_case_commits_helper.rb)
  with `INSTANCE_COLUMN_PRESETS` for the four presets (default,
  performance, convergence, all). The cell renderer is
  `_instances_cell.html.haml` — one `case col[:id]` dispatch with
  per-column formatting (`%.2f m` for runtime, `%.3e` for star
  age, mem_rn-in-KB → MB conversion, em-dash for missing values).
  Column widths were tuned (status label dropped from 220px to
  180px; cell horizontal padding from `px-3` to `px-2`) so the
  default eight-column set fits the 1320px container without
  horizontal scroll on standard desktop viewports.
- **localStorage persistence.** The column picker writes the
  active set to `mesa.test_on_commit.columns.v1` after every
  change; on the next render the controller hydrates from there
  before falling back to the server-supplied default. Survives
  navigation between test cases on the same commit. Replaces the
  broken cookie-based version flagged in the original Step 3
  notes.
- **Per-row search blob.** Each instance row carries
  `data-row-search="<computer name> <checksum>"` (lowercased
  server-side). The `instance-filter` controller does a simple
  `includes()` match against the input value. Cheap O(rows) on
  every keystroke, fine for the ≤25-instance ceiling these pages
  typically hit.
- **Status segmented control.** Three buckets — fail / pass /
  pending — plus "All". Counts pre-rendered server-side from the
  `instances_for_display` payload so the chip labels read
  truthfully even before the controller boots.
- **Last-inlist semantics for per-inlist metrics.** Model Number,
  Star Age, and Inlist Retries read off the last inlist run by
  the instance (ordered by `instance_inlists.order`). Mirrors the
  legacy view's "last inlist's numbers in the overview row"
  behavior. The Num Retries column sums `num_retries` across
  every inlist for the "total retries across the whole run"
  reading the design's column label implies. The Retries column
  (per-inlist) is shown as an em-dash for now — the existing
  `instances_for_display` payload doesn't expose per-inlist
  retries, only `redos`, so the column reads honestly rather than
  silently aliasing to the cumulative count from the next column
  over.
- **Pivot buttons:** GitHub (top-right of the left column in
  the headline's bottom tier) and `Full history` (top-right of
  the right column, in line with "History of star/X").
  Symmetric placement across the two-column split. The legacy
  `← All tests on <sha>` button was dropped — the breadcrumb
  back arrow and the in-headline test picker dropdown already
  cover that pivot. The legacy older/newer breadcrumb arrows
  were also removed; the subway map's adjacent stations cover
  sequential walking with status color + popovers + SHA labels
  at a glance.
- **Optional `?computer=` focus highlight.** When the user clicks
  a matrix cell on the commit detail page that links here, the
  modern view tints the matching computer's row with `bg-brand-soft`
  so it's visually obvious which row triggered the navigation.
  No-op when the param is absent.
- **Dev-preview shortcut for headless screenshots.**
  `DevPreviewController#commits` now accepts `?return_to=<path>`
  so a headless Chrome smoke test can authenticate-then-screenshot
  in a single navigation. The check rejects protocol-relative
  values (`//foo`) so it can't become an open redirect.

Subsequent follow-ups landed in the same branch (2026-05-23 ff):

- **Test-picker dropdown in the headline.** The static test
  name pill became a clickable picker that lists every TCC
  on this commit, sorted worst-first by status (failing →
  mixed → checksum-only → passing → untested), then by
  module (star → binary → astero per `TestCase.modules`),
  then alphabetically by test name. Each row carries a
  colored status dot. A typed search filter sits sticky at
  the top of the dropdown for branches with hundreds of
  tests. New: `TestCaseCommitsHelper#sorted_commit_tccs`,
  `#tcc_status_rank`, `#tcc_status_dot_class`, `#tcc_status_token`,
  `#tcc_status_word`; partial `_test_picker.html.haml`;
  controller `test_picker_controller.js`.
- **Test-scoped subway map in the headline's right column.**
  Sister of the commit-detail hero's `_hero_subway_map` but
  with single-color stations (one status per commit) instead
  of the inner/outer ring split commit-show uses for build vs
  tests. Five stations centered on the focused commit; the
  anchor is enlarged + brand-ringed. Non-focused stations
  link to that commit's test-on-commit page and reveal
  popovers (SHA · age · message · author · this test's
  status) via the shared `subway_map_controller.js`. Data
  loaded in the controller via
  `Branch#focused_commit_window(commit, size: 5)` plus a
  per-test TCC lookup.
- **Headline restructure to mirror commit-show's "feel".**
  Two tiers separated by a hairline: status sentence
  full-width on top, then a `lg:grid-cols-2` split with
  commit identity (message + expander + author + time +
  GitHub button top-right) on the left and the test-history
  capsule (subway map + Full history button top-right) on
  the right. Symmetric placement of GitHub and Full history
  in each column. Below `lg` (1024px), the columns stack
  with the subway underneath. The legacy "All tests on
  `<sha>`" button is gone — the breadcrumb back arrow + the
  test picker cover that pivot.
- **Tab strip + Logs tab.** The page picked up a Summary /
  Logs tab strip mirroring commit-show. The Logs tab proxies
  the three per-test log files (`out.txt`, `mk.txt`,
  `err.txt`) hosted at the Flatiron logs server via a new
  `test_case_commits#log` action; a sibling `#log_status`
  action HEAD-probes all three types per (commit, computer,
  test) and returns a per-type availability JSON, cached for
  10 minutes. Per-type 404 messages name the exact missing
  file and point at sibling types. The proxy machinery
  (`fetch_log`, `probe_log_url`, error types, byte cap,
  timeouts, status TTL) was extracted from
  `CommitsController` into a new
  [`LogProxy`](app/controllers/concerns/log_proxy.rb)
  concern that both controllers include. Routes added:
  `/:branch/commits/:sha/test_logs/:module/:test_case/:computer/:type`
  and `/test_logs_status/...`. Type validation lives in the
  controller (`LOG_TYPES`) so the route constraint can stay
  open enough for URL template substitution.
- **Per-row "logs ↗" link.** Every instance row in the
  Summary tab gets a tiny mono link next to the flag icons
  that jumps to `?tab=logs&computer=<canonical-name>`. The
  tabs controller's `switchFromLink` action dispatches a
  `tabs:request` event with the `computer` param; the
  `test_logs` controller listens and pre-selects that
  computer (falling back to a sibling log type if the
  default `out.txt` doesn't exist). Each link's
  `test_log_row_link_controller.js` does an async HEAD
  probe on connect and hides the link when no logs exist
  for that (commit, computer, test). The URL parameter uses
  the canonical `Computer.name` (not the instance row's
  `computer_name` which may be a compiler-variant suffix
  like `bluebear_ifort`) so the cross-panel handoff lands
  on the right picker button.
- **Older/newer breadcrumb arrows removed.** The subway
  map's adjacent stations cover sequential walking with
  status color + popovers + SHAs at a glance.
- **Dev-preview shortcut for headless screenshots.**
  `DevPreviewController#commits` accepts `?return_to=<path>`
  so a headless Chrome smoke test can authenticate-then-
  screenshot in a single navigation. The check rejects
  protocol-relative values (`//foo`) so it can't become an
  open redirect.

Files added (cumulative):

- `app/controllers/concerns/log_proxy.rb`
- `app/helpers/test_case_commits_helper.rb`
- `app/views/test_case_commits/_breadcrumb.html.haml`
- `app/views/test_case_commits/_headline.html.haml`
- `app/views/test_case_commits/_test_picker.html.haml`
- `app/views/test_case_commits/_subway_map.html.haml`
- `app/views/test_case_commits/_show_tab_strip.html.haml`
- `app/views/test_case_commits/_tab_summary.html.haml`
- `app/views/test_case_commits/_tab_logs.html.haml`
- `app/views/test_case_commits/_instances_panel.html.haml`
- `app/views/test_case_commits/_instances_table.html.haml`
- `app/views/test_case_commits/_instances_cell.html.haml`
- `app/views/test_case_commits/_column_picker.html.haml`
- `app/javascript/controllers/column_picker_controller.js`
- `app/javascript/controllers/instance_filter_controller.js`
- `app/javascript/controllers/test_picker_controller.js`
- `app/javascript/controllers/test_logs_controller.js`
- `app/javascript/controllers/test_log_row_link_controller.js`

Files modified:

- `app/controllers/test_case_commits_controller.rb` — sheds the
  Bootstrap-era `@default_columns` / `@specific_columns` /
  `@inlist_data` setup; loads `@instance_rows`, `@commit_tccs`,
  `@subway_window`, `@log_computers`; computes `@status_word` /
  `@checksum_word` / `@active_tab`; adds `#log` and
  `#log_status` actions; opts `#show` into `layout "modern"`.
- `app/controllers/commits_controller.rb` — proxy +
  probe + error types lifted into the `LogProxy` concern;
  `#build_log` and `#build_log_status` now thin wrappers
  that call `LogProxy.fetch_log` / `LogProxy.probe_log_url`.
- `app/controllers/dev_preview_controller.rb` — `?return_to=`
  passthrough.
- `config/routes.rb` — `test_case_commit_log` +
  `test_case_commit_log_status` routes, mounted before the
  catch-all `test_case_commit_path`.
- `app/views/test_case_commits/show.html.haml` — wraps in
  the tabs controller, renders the tab strip, iterates the
  panel partials.

Verification: full spec suite green (209 examples, 0
failures). Headless Chrome screenshots at
`/main/commits/45f1056/test_cases/star/black_hole` (mixed
status, 3 instances, 1 checksum) render the new headline,
subway map, and both Summary and Logs tabs correctly.
Direct curl-tested the new endpoints: `test_logs_status`
returns the per-type JSON; `test_logs` returns the friendly
multi-line 404 message; unknown type returns 400; unknown
computer returns 404 with a clear "no instances on X"
message.

#### Step 7 known followups (not blocking)

- **Live-driven JS verification.** Headless Chrome covered the
  initial render only — no smoke test exercised the column
  picker dropdown click, status segment click, or search-input
  filter live. The hooks are all present and mirror existing
  controller patterns, but the first user-driven interaction in
  the dev DB is the real test.
- **Finer-resolution + restart-photo signals.** Removing the
  variant column means the `resolution_factor < 0.99` and
  `restart_photo.present?` rows lose their inline indicator
  (the legacy Bootstrap view rendered a `search-plus` and
  derived restart info from the `success_type` label). Photo
  restart still surfaces through `success_type` ("PASS: Photo
  checksum"), but finer-resolution rows are now indistinguishable
  from default ones. If users complain, add a fifth status-cell
  icon for fine resolution; the icon set already handles 4 flag
  cases cleanly so a fifth fits the visual budget.
- **Per-inlist retries column.** Either populate
  `instances_for_display` with `inlist[:retries]` so the
  per-inlist Retries column can render real values, or drop the
  column from the preset menu entirely. Currently shown as `—`.
- **Inlist-pill drill-down.** The legacy view had per-inlist
  tabs that swapped the entire table for one inlist's data. The
  modern design doesn't show that pattern, and the matrix lens
  on commit detail already gives users a "drill into a specific
  computer's run" path via the popover. Worth revisiting once
  users complain that the overview row hides per-inlist drift.

### Step 8 — Wing the rest

Pages without designs, in priority order:

- `test_cases#show` (test-across-commits) — **landed.** Three
  tabs sharing the test-on-commit visual frame: **History** (one
  row per TCC with per-row mini-matrix + popover with degradation
  metrics, default), **Trend** (uPlot line chart of a chosen
  metric vs commit index for the top-3 most-common
  `(computer, threads, run_optional)` config tuples + status strip
  + vertical anchor marker), **Submissions** (per-instance table
  for a chosen computer over the window — picker auto-selects the
  most-active). All three tabs share a single time-window toolbar
  (anchor commit + window size 25/50/100/250 + pan ←/→) and a
  collapsed-tier headline. Re-centering on a clicked Trend point
  or a History-row crosshair pivots the whole page. URL contract:
  `?tab=&center=&window=&metric=&computer=`. See
  "test_cases#show design notes" below.
- `computers#index` and `computers#show`
- `test_instances#index`, `test_instances#search`,
  `test_instances#show`
- `submissions` UI (if any beyond the API)
- Admin/users pages

For each: read the existing Bootstrap view, identify the data
shown, and rebuild in the same Tailwind vocabulary. Lean on the
shared components from Step 3. When in doubt, match the
information density and color encoding of the designed pages.

#### `test_cases#show` design notes

Resolved choices (locked in before Phase A landed):

- **Default metric on Trend tab**: `runtime_minutes`. Most
  universally meaningful and doesn't require an inlist pick.
- **X-axis**: commit index along the branch, equally spaced — not
  commit time. Equal spacing makes regression points easier to find
  visually; the time information is still in the per-point tooltip.
- **Custom inlist-data series**: when a `custom:<name>` metric is
  picked, use the first inlist on each instance that contains
  that datum name. Future enhancement: add an inlist sub-picker
  that surfaces only when the chosen datum appears in multiple
  inlists.
- **Top-N config tuples**: 3 by default. Few computers do heavy
  testing, so 3 covers the common cases without making the chart
  noisy. Power users get a "+more" panel listing every config
  with counts.
- **Chart library**: uPlot. ~45 KB, MIT, pin via importmap. D3
  is the wrong tool here — we don't need its DSL, just a fast
  XY chart with multiple series and gaps.
- **Passage strip**: ~60 most-recent commits on the branch, one
  small pill per commit colored by `tcc.status`. Horizontally
  scrollable. Reuses the `subway-map` Stimulus controller for
  hover popovers.

**Future note** — the Trend tab payload + Stimulus controller
should be lifted up to `test_case_commit#show` as an additional
"Trend" tab once `test_cases#show` ships. There the chart would
be scoped to "this test across the last N commits centered on
this one", giving regression hunting a per-commit drilldown
without leaving the test-on-commit view. Out of scope for the
initial Step 8 port; build the foundation here, reuse it there
later.

#### `computers#index` + `computers#show` design notes

Landed in Steps 8g + 8h. Two pages, one focused chunk — the user
clicks from index → show, so they share visual vocabulary and the
same headline rhythm.

- **Breadcrumb on top.** `← <user>'s computers / <computer>` on
  show; `← <user> / Computers` on index (or `← Admin / Computers`
  on the admin all-view). Same back-arrow + slug pattern the
  test_case_commits / test_cases pages use.
- **Headline card with the same single-tier sentence rhythm as
  test_cases#show.** Index reads "N computers maintained by
  `<user>`" (or "across all users" on the admin view) with an
  "Add computer" CTA top-right when `self_or_admin?`. Show reads
  "`<name>` is a `<platform>` machine maintained by `<user>`" with
  Edit + Delete CTAs top-right. The show page adds a Tier 2 below
  a hairline that splits at `lg+` into Hardware (Platform /
  Processor / RAM) on the left and Usage (CPU hours over last
  24h / last year / all time + the inception date) on the right,
  mirroring the test_case_commits hero's commit-identity / test-
  history capsule split.
- **Sticky-thead tables in both pages.** Index has 5 columns
  (Name / Platform / Processor / RAM / actions) plus an optional
  Maintainer column for the admin view. Show's submissions table
  has 7 (Submitted / Commit / Build / Tests / Compiler / SDK /
  Math backend) — same 7 the legacy Bootstrap view had, per the
  wing-it "preserve information density" rule. Build status is a
  semantic pill (Built / Failed / Not reported) matching the
  banner palette on commit-show; everything else is mono.
- **Tests column collapses to a link when there's exactly one.**
  Submissions with a single test instance show the test name as a
  link to the test's history page rather than a bare "1" count —
  matches the legacy view's "test_case.name appears in the cell
  when count == 1" behavior.
- **Modern Kaminari paginator theme.** Both pages introduced
  `app/views/kaminari/modern/_paginator.html.haml` (plus `_page`,
  `_prev_page`, `_next_page`, `_gap`). Brand-fill for the active
  page; neutral mesa-btn-styled buttons for the rest; Older/Newer
  arrows reuse the mesa_icon set. Pages opt in with
  `paginate @scope, theme: "modern"`. The Bootstrap-era partials
  at `app/views/kaminari/` stay in place for un-migrated pages.
- **Delete actions use `button_to` + `turbo_confirm`.** The modern
  layout ships only Turbo (no rails-ujs), so `link_to ...,
  method: :delete` is dead. `button_to` renders a real form so
  Turbo's confirm flow + DELETE handling work without any custom
  JS. Reusable everywhere the wing-it pages need destructive
  actions.
- **Sort dropdown** on the index (Most recent activity /
  Maintainer (A→Z) / Computer name (A→Z)) — same
  `dropdown_controller` the test_cases submissions Computer
  picker uses. Backed by `Computer.ordered(sort)`. Maintainer
  option hidden on the per-user view since there's only one
  maintainer. Picking a sort always resets pagination.
- **Bulk-delete submissions on `computers#show`** —
  filter-then-select-then-confirm. The filter toolbar
  (`?from=&to=&sha=`) sits at the top of the submissions card
  driven by new `Submission.submitted_between` +
  `Submission.for_commit_sha` scopes. Per-row checkboxes (only
  rendered for `self_or_admin?`), an indeterminate-aware
  "select all on this page" header checkbox, and a sticky
  brand-soft selection bar. When the filter matches more rows
  than fit on one page AND every visible row is selected, the
  bar grows a "Select all M matching" link that flips the
  destroy form into `select_all_matching=1` mode — lets a
  maintainer take out a whole filtered batch without manually
  checking 25 boxes per page. Confirmation is an HTML5
  `<dialog>` (`showModal()`) with a destructive-tone
  confirm. POSTs to a new
  `ComputersController#destroy_submissions`
  (`DELETE /users/:user_id/computers/:id/submissions`),
  protected by `authorize_self_or_admin`, scoped at
  `@computer.submissions` for IDOR safety, capped at
  `BULK_DESTROY_LIMIT = 500` so the
  `Submission#after_commit :update_commit` chain doesn't
  hang a single request. The
  `submission_selection_controller.js` Stimulus controller
  owns the checkbox state + sticky bar visibility + modal
  open/close + dynamic count interpolation in the bar AND
  modal AND submit button — all reading the same `count`
  target set. A small modern-layer block in
  `app/assets/tailwind/application.css` centers the dialog
  and adds the scrim backdrop (the browser default for
  `<dialog>` is transparent — easy to miss).

### Step 9 — Cleanup

- Remove the legacy gems listed in "Stack changes" above.
- Delete `app/assets/javascripts/*.js` files that have been
  replaced by Stimulus controllers.
- Delete `app/assets/stylesheets/*.scss` files superseded by
  Tailwind. Sprockets may still serve generated assets if needed.
- Update `Gemfile`, run `bundle install`, regenerate `Gemfile.lock`.
- Clear `tmp/cache/bootsnap` once after gem removals.
- Update `CLAUDE.md`: drop the "Bootstrap 4, jQuery, Sprockets,
  Turbolinks" line under reality checks.
- Update `docs/roadmap.md`: mark Phase 4 complete.

## Pages without designs ("wing it" policy)

These don't have specific designs in the handoff. The policy:

- **Reuse the same components** (StatusDot, BuildStatusPill,
  TestStatusPill, FlagChip, BranchPicker, etc.) from Step 3.
- **Match the visual vocabulary**: same tokens, same density, same
  patterns (chips for filters, cards for grouped content, monospace
  for SHAs / computer names / test names).
- **Preserve the existing information density.** The Bootstrap
  pages cram a lot of data into small spaces. The new design's
  pages do too. The wing-it pages should follow suit, not get
  airier just because there's no reference.
- **No new features.** Wing-it pages are pure ports. Anything more
  interesting goes in the feature backlog.

## Decisions to make in Step 0

- **Importmap vs jsbundling.** Default importmap. Switch only if
  Stimulus tooling forces our hand.
- **HAML vs ERB for new partials.** The existing app uses HAML.
  Stay with HAML for consistency. (Tailwind classes work fine in
  HAML, just long.)
- **Theme toggle default.** "System" (follows
  `prefers-color-scheme`) per the prototype.
- **Per-route branch encoding.** Continue using path-based branch
  (`/:branch/commits/...`); the inline branch chip switches by
  changing the URL.
- **Pagination.** Keep Kaminari; works fine with Turbo Frame
  partials.

## Out of scope

- **Real-time updates** (Turbo Streams broadcasts on test
  submission). Could be a separate phase; not required for the
  visual rewrite.
- **A redesigned `test_instances` cross-commit list.** The handoff
  explicitly punts on this. Wing it per Step 8.
- **A redesigned `branches` and `computers` index.** Wing it.
- **A command palette (⌘K).** The prototype shows a mock; not
  implementing.
- **Live log streaming.** Logs tab can show the existing HEAD-probed
  log link behavior; full streaming is its own project.

## When this lands

Suite is expected to stay flat or grow modestly. The visual rewrite
itself doesn't need new specs beyond:

- A spec per aggregation helper (`commit_state`,
  `test_computer_matrix`, `sparkline_data`,
  `instances_for_display`).
- The existing page-render smoke specs continue to pass against the
  new views.
- A small handful of system specs for the critical interactions:
  theme persistence, branch picker, column picker, copy button.

When Step 9 closes and `bundle exec rspec` is green, Phase 4 is
done.
