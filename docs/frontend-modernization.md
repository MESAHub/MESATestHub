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

- Layout: headline with branch chip → 4 stat tiles → sparkline panel
  → search/filter toolbar → grouped commit table.
- Replace the existing top-nav branch dropdown with the inline
  branch chip pattern.
- Use `Branch#sparkline_data` for the panel.
- Age grouping via the `ageBucket` logic from `data.js` — port to
  a Ruby helper.
- Status filter chips backed by the new `commit_state` model.

Verification: all nine demo scenarios from the handoff render
correctly; pagination + filtering work; dark mode toggle persists.

### Step 6 — Commit detail (`/:branch/commits/:sha`)

The biggest page. Reference: `03-` through `08-prototype.png`.

- Breadcrumb with mini branch chip.
- Hero card with pill row, message, author, stats, sparkline.
- Conditional banners (BuildFail, BuildPartial, Failing, Mixed,
  Pending) — derive from `commit_state`.
- Context-sensitive default tab (build issues → Computers, failures
  → Tests, otherwise Summary). URL-controlled override.
- Tabs: Summary (matrix) / Tests / Computers / Diff vs last pass /
  Logs. Use Turbo Frames so tab switches are partial loads, not
  full navigations.
- Matrix legend above the matrix in Summary tab.

The "Diff vs last pass" tab needs a new comparison helper —
"cells that changed status since the last clean commit on this
branch." Use the recursive CTE topology to find the last clean
commit, then diff matrices.

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
