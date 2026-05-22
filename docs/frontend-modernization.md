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
  - `test_cases/show.html.haml` (test-across-commits)
  - `computers/index.html.haml`, `computers/show.html.haml`
  - `computers/test_instances_index.html.haml`
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

**Status: mostly landed (2026-05-22)**. Scaffolding (2026-05-21)
established structure, helpers, and skeleton tabs. The follow-up
work in the same week filled out the matrix, the Tests-tab filter
chips, the in-page log proxy + lazy load + availability probe,
the per-segment subway-map arrows, the soft-color banner fills
with cross-panel filter handoffs, and the test-classification
rule that calls "pass + pending neighbors" passing (not pending).
What remains is Tests-tab search + per-row computer ribbon,
Computers-tab card polish, and a few small Diff-tab tweaks —
itemized at the end of this section.

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
  `?tab=tests&filter=failing`; a Computers-tab failed-build card
  packs `?tab=logs&computer=rusty`. The same URL works as a
  direct deep link.
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
  downgrade — the Summary matrix's cell-aware filter still
  surfaces those rows so the user can see *which* computers
  haven't reported, but the hero stats and Tests-tab filters
  treat them as passing. `:pending` only fires when no computer
  has reported a pass at all.

Substep follow-ups (pending — not blocking PR):
- **Tests tab:** free-text search across test names, module
  filter dropdown, per-row mini computer ribbon (replacing the
  current "1 fail · 105 pass" summary text with one small cell
  per computer).
- **Computers tab:** SDK info chip on each card, "maintained by
  <user>" line linking to the owner, "last successful build"
  link on no-build cards, conditional log link gated on the
  per-computer probe (today's link is unconditional).
- **Diff tab:** the cell-icon visualisation from the handoff
  (matrix cell drawings rather than "pass → fail" text), and a
  summary line at the top.
- **Sticky matrix header.** On commits with many failing tests
  the rotated computer-name header row scrolls out of view.
  `position: sticky` would keep it pinned.

### Step 7 — Test on commit (`/:branch/commits/:sha/tests/:module/:test`)

Reference: `09-`, `10-`, `11-prototype.png`.

- Color-coded headline sentence.
- Compact commit context.
- Instances table with column picker (Stimulus controller from
  Step 3).
- Available columns: 20 total grouped into Run / Output /
  Convergence. Most columns map to existing `TestInstance` /
  `InstanceInlist` fields; spec the column → field mapping
  carefully.

This page replaces the current `test_case_commits#show` — verify
the existing route still works.

### Step 8 — Wing the rest

Pages without designs, in priority order:

- `test_cases#show` (test-across-commits) — similar in spirit to
  commit detail's per-row computer ribbon, but the rows are
  commits and the columns are computers.
- `computers#index` and `computers#show`
- `test_instances#index`, `test_instances#search`,
  `test_instances#show`
- `submissions` UI (if any beyond the API)
- Admin/users pages

For each: read the existing Bootstrap view, identify the data
shown, and rebuild in the same Tailwind vocabulary. Lean on the
shared components from Step 3. When in doubt, match the
information density and color encoding of the designed pages.

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
