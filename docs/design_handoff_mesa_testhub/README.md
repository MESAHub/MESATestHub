# Handoff: MESA Test Hub Redesign

A redesign of the MESA Test Hub — a developer-facing dashboard for inspecting CI test results across many computers for the MESA stellar astrophysics codebase.

This bundle is the output of an iterative design pass. It is meant as the **starting point** for an ongoing redesign, not a finished spec.

---

## About these files

The HTML files in this bundle are **design references**, not production code. They are a React + Babel-in-the-browser prototype rendered from inline JSX with hand-rolled CSS custom-property theming.

**Your job is to recreate these designs in the target codebase.** The MESA Test Hub currently ships as a Bootstrap-based app and is migrating to Tailwind. Implement the patterns shown here using the existing Tailwind setup (or whatever framework decisions have been made since this handoff). Treat the HTML as a visual + behavioural reference; do not copy the Babel-in-browser approach.

The design tokens (CSS custom properties under `styles/tokens.css`) are the canonical source of truth for colors, spacing, radii, and typography. Port them to your Tailwind config or equivalent.

## Fidelity

**High-fidelity.** Pixel-level layout, color, type, spacing, and interaction states are intentional and should be matched. Components, copy, and information architecture should be reproduced as-is, then adapted to the codebase's component primitives.

The mock dataset (in `prototype/data.js`) is illustrative — it models specific scenarios on purpose to demonstrate each state. Wire real data into the same shape and the screens should "just work".

---

## What's in this bundle

```
design_handoff_mesa_testhub/
├── README.md                ← you are here
├── screenshots/             ← annotated reference renders
├── assets/
│   ├── mesa-mark.svg        ← the M-only mark (used as favicon + nav)
│   └── mesa-wordmark.svg    ← full MESA wordmark
├── styles/
│   └── tokens.css           ← design tokens (light + dark)
└── prototype/
    ├── index.html           ← entry point — load this to run the prototype
    ├── data.js              ← mock data + state-aggregation helpers
    ├── components.jsx       ← shared atoms (Sparkline, StatusMatrix, pills, icons)
    ├── screens.jsx          ← CommitsList, CommitDetail, TestOnCommit
    ├── app.jsx              ← top nav, routing, theme controller
    └── tweaks-panel.jsx     ← (ignore — design-tool tweak controls, not part of the app)
```

To run the prototype locally: open `prototype/index.html` in a browser. Routes are hash-based — try `#/`, `#/commit/c5e8a01`, `#/test/aa27a08/20M_z2m2_high_rotation`.

---

## Screens

### 1. Commits list (`/commits` — entry point)

Screenshots: `01-prototype.png` (light), `02-prototype.png` (dark)

**Layout**: page-headline-with-branch-chip → stat-tile row → sparkline panel → toolbar (search + filter) → grouped table of commits.

**Headline**: "Commits on `<branch>` ▾" — the branch name is rendered as a brand-tinted, monospaced pill that opens the branch picker on click. This replaces the previous out-of-the-way top-nav branch dropdown.

**Stat tiles** (4 small cards): Clean / Failing tests / Mixed results / Build issues. Each is a colored numeric count tied to its category.

**Sparkline panel**: last 12 commits as small two-tone bars (build status top, tests status bottom). Categorical color, not proportional — see "Status model" below. The current commit (when on detail page) gets a brand-color outline. Click a bar to jump to that commit. The legend below uses tiny two-tone swatches.

**Toolbar**: free-text search + segmented filter chips: All / Failing / Mixed / Build issue / Running / Clean.

**Commit table**: 8 columns.
| col | content |
| --- | --- |
| dot | StatusDot — worst-of(build, tests) prioritized |
| Commit | message (truncated) + sub-line: `#1001 · 11 files · +428 −317` |
| SHA | 7-char abbreviated, brand color, monospace |
| Author | initials avatar + name |
| **Build** | BuildStatusPill — green/amber/red |
| **Tests** | TestStatusPill — green/red/amber/blue/gray |
| Flags | compact `🔧 2 · ≠ 3 · + 1` icon-counts |
| When | relative time (right-aligned) |

**Age grouping**: rows are split by section headers — Today / Yesterday / Earlier this week / Last week / Earlier this month / Older. Bucket-computation logic is in `data.js` → `ageBucket(iso)`. Empty buckets are hidden.

### 2. Commit detail (`/commit/:sha`)

Screenshots: `03-prototype.png` (clean), `04-prototype.png` (failing), `05-prototype.png` (build partial), `06-prototype.png` (pending), `07-prototype.png` (mixed), `08-prototype.png` (dark mode).

**Layout**: breadcrumb → hero card → conditional banner(s) → tab strip → tab content.

**Breadcrumb**: `← Commits / ⎇ <branch> ▾ / <sha>` — the branch chip stays clickable here too, just smaller. Prev / next commit buttons on the right.

**Hero card**:
- Top row of pills: `BuildStatusPill`, `TestStatusPill`, `PR #N`, plus flag pills if applicable (`🔧 N FPE`, `≠ N checksum ≠`, `+ N full inlists`)
- Commit message (h1)
- Author / time / files-changed line
- Right side: `View on GitHub` + `Copy SHA` buttons
- Stat row: Builds (`N/M`) · Tests failing · Mixed · Pending · FPE/≠ · Sparkline (last 12 with current outlined)
- Full SHA footer (monospace)

**Banners** (can stack): rendered conditionally based on state.
- `BuildFailBanner` — when all computers failed to compile
- `BuildPartialBanner` — when some did, some didn't
- `FailingBanner` — when uniform failures exist; "View diff" jumps to Diff tab
- `MixedBanner` — same test passes on some computers, fails on others ("likely points to a computer-specific issue")
- `PendingBanner` — info-blue, when runs are still going

**Context-sensitive default tab** (in `CommitDetail`):
- Build issues → **Computers** tab opens by default
- Test failures or mixed → **Tests** tab
- Clean / flagged / pending only → **Summary**

**Tabs**: Summary · Tests · Computers · Diff vs last pass · Logs. Numeric badge next to each: Tests gets red (when failing) or amber (when only mixed/flagged); Computers gets deep-red (`buildfail`) when all builds failed, amber when partial.

**Summary tab**: Test×Computer matrix on the left (see Matrix below), Computers + Activity sidebars on the right.

**Tests tab**: Toolbar (search · status filter · module filter) → list of tests with per-row computer ribbon (mini matrix). Click a row to open the test-on-commit view.

**Computers tab**: Per-computer cards, sorted with problem computers first. Each card has SDK info, mini-stats (pass/fail/run/FPE/≠), build status. No-build cards prominently display "Compilation failed" and link to build logs.

**Diff vs last pass**: lists every cell that changed status since the last clean commit — new failures, new mixed states, new FPE/checksum flags.

**Logs tab**: computer picker + log view. Content varies by computer state (build log for compile fails, test log for failures, summary for passing).

### 3. Test-on-commit (`/test/:sha/:testId`)

Screenshots: `09-prototype.png` (passing, one checksum), `10-prototype.png` (multi-instance failing), `11-column-picker.png` (two unique checksums)

Replaces the prior "Test Instance" page. Shows **multiple instances** of one test on one commit, with toggleable columns of numerical data.

**Headline sentence** (large text, color-coded keywords): *"`test_name` (`module`) is **passing** in **<sha>** with **one unique checksum**."*

Status word colors:
- `passing` → success green
- `failing` → danger red
- `mixed`   → warning amber
- `running` → info blue

Checksum word: "one"/"two"/"three" unique checksums. When >1, the value turns amber and a "Bit-for-bit reproducibility broken" sub-line appears listing the divergent checksums.

**Compact commit context** below the headline: author avatar, message snippet, time, action buttons (GitHub, back, test history).

**Instances table** with column-picker dropdown — see "Column picker" below.

Each row is one instance — typically `(computer, variant)` pairs where `variant` is the run kind (`out` = fresh run, `mk` = photo restart). Rows can also exist for multiple inlists per computer.

Available columns (20 total), grouped:
- **Run**: Computer, Variant, Date, Threads, Spec, Runtime, RAM
- **Output**: Status (always on), Checksum, Model №, Steps, Star Age
- **Convergence**: Cum. Retries, Retries, Redos, Solver Iters, Solver Calls, Calls Failed, log Rel E, Num Retries, Inlist Retries

Status column is left-anchored. Inline flag icons (`🔧`, `≠`, `+`) appear next to the status label when applicable. When checksums diverge across rows, the divergent values render in amber.

### Test×Computer matrix (atom, used in Summary tab)

Screenshot: visible in `03-prototype.png` through `07-prototype.png`.

Two-axis grid. Rows are tests (label = `module/test_name` in monospace, module-prefix dimmed). Columns are computers, labels rotated vertical for compactness.

**Cell encoding**:
| status | flags                | rendering |
| ------ | -------------------- | --------- |
| pass   | none                 | solid `--success` |
| pass   | inlists_full         | solid `--success` + blue `+` corner badge |
| pass   | fpe                  | solid `--warning` + white `🔧` glyph centered |
| pass   | checksum             | solid `--warning` + white `≠` glyph centered |
| pass   | fpe + checksum       | solid `--warning` + `≠` glyph + corner `🔧` |
| fail   | any                  | solid `--danger` + white `×` glyph |
| skip   | -                    | solid `--skipped` + white `−` |
| pending| -                    | diagonal info-blue stripe + clock glyph |
| no-build| -                   | diagonal mute-gray stripe |

Cells are 26×26 (22×22 in compact mode). Click opens the test-on-commit view, scrolled to the clicked computer.

A **legend** appears above the matrix in the Summary tab — clearly labels all of the above so users learn the encoding once.

---

## Status model (critical to get right)

The system tracks **two orthogonal dimensions** per commit. There is no "overall" status — surface both.

### Build status — `state.build.status`
```
all-ok    every computer compiled
some-fail at least one but not all
all-fail  every computer failed to compile
```
Also: `builtComputers[]`, `failedBuildComputers[]`.

### Tests status — `state.tests.status`
Single-token for compact display, worst-first prioritization:
```
fail            at least one test failed uniformly on every computer that ran it
mixed           at least one test passed on some computers, failed on others
pending         at least one test still running
pending-partial pending + some already passed
all-pass        every test ran and passed
not-run         no tests ran (usually because all builds failed)
```
The state also carries multiple booleans because multiple of these can be true simultaneously:
- `tests.hasUniformFail`
- `tests.hasMixed`
- `tests.hasPending`
- `tests.uniformFailingTests` (count)
- `tests.mixedTests` (count)
- `tests.pendingTests` (count)

**Mixed is distinct from failing.** Same test passing on some computers and failing on others is a different signal (usually a computer-specific issue) — render it amber, not red. Both can co-exist on a commit.

### Cell flags — `cell.flags`
Flags are orthogonal to status; a passing test can carry any combination:
- `fpe` — floating-point exception raised during run (test still passed numerically — worth investigating)
- `checksum` — bit-for-bit reproducibility broken (test passed but output checksum diverged from reference)
- `inlists_full` — the run exercised **all** optional inlists, not just the default set (informational positive)

`fpe` and `checksum` recolor the cell amber and add a glyph. `inlists_full` keeps the cell green and adds a blue corner badge.

**Do NOT introduce a top-level "Flagged" commit status.** Flags are individual signals shown as separate counts/pills. This was an earlier mistake corrected in this design.

### Aggregation logic
See `data.js` → `getCommitState(sha)`. Key behaviors:
- A test that has all-fail across built computers contributes to `uniformFailingTests`, not `mixedTests`.
- A test with at least one fail + at least one pass contributes to `mixedTests` (not `uniformFailingTests`).
- A test with any pending result contributes to `pendingTests` (in addition to its other classification).

### Sparkline encoding
Each bar is **categorical, not proportional**. Top sliver (≈18% of bar height) = build status; bottom block = tests status. Mapping:

| build top | meaning |
| --- | --- |
| green | all builds OK |
| amber | partial build |
| deep red | all builds failed |

| tests bottom | meaning |
| --- | --- |
| green | all-pass |
| amber | mixed |
| red | failing |
| blue | pending |
| gray | not run |

The current commit (when on its detail page) gets a brand-color outline rect drawn around its bar.

---

## Design tokens

See `styles/tokens.css` for the full definitions. Summary:

### Colors

**Brand**: `#3A56FD` (primary). Use for SHAs, links, primary buttons, sparkline current-commit outline, brand-tinted soft backgrounds.

**Semantic** (light theme; tokens.css has dark overrides too):
| token | hex | usage |
| --- | --- | --- |
| `--success` | `#1a7f37` | clean / pass |
| `--success-soft` | `#d8f5df` | pill backgrounds |
| `--success-soft-text` | `#0a5825` | pill text |
| `--danger` | `#cf222e` | test failure |
| `--danger-soft` | `#ffe4e6` | |
| `--danger-soft-text` | `#a40e26` | |
| `--warning` | `#9a6700` | mixed / flagged / partial build |
| `--warning-soft` | `#fef6cf` | |
| `--warning-soft-text` | `#6b4900` | |
| `--buildfail` | `#6e1818` | total build fail — deeper than `--danger` on purpose |
| `--buildfail-soft` | `#f3dada` | |
| `--buildfail-soft-text` | `#6e1818` | |
| `--info` | `#1f6feb` | pending / informational ("ran full inlists") |
| `--info-soft` | `#ddeaff` | |
| `--info-soft-text` | `#0a3a8f` | |
| `--skipped` | `#6a737d` | skip / no-data |

**Surfaces** (light):
- `--bg` `#ffffff`, `--bg-subtle` `#f7f8fa`, `--bg-muted` `#eceef2`, `--bg-elev` `#ffffff`
- `--border` `#d8dde4`, `--border-strong` `#b7bec9`, `--border-subtle` `#e6e8ec`

**Foreground** (light):
- `--fg` `#1f2328`, `--fg-muted` `#57606a`, `--fg-subtle` `#8b949e`

**Dark mode** flips all surfaces / foregrounds while keeping the brand intent. Activated by `data-theme="dark"` on `<html>`. The dark-mode brand value brightens to `#6B82FF` for contrast. See `tokens.css` for full mapping.

### Radii
`--r-sm 4px`, `--r-md 6px`, `--r-lg 10px`, `--r-xl 14px`

### Shadows
`--shadow-sm`, `--shadow-md`, `--shadow-lg` (defined for both themes — dark uses darker values)
`--shadow-focus` — `0 0 0 3px var(--brand-ring)` — use on focus-visible

### Typography

The prototype lets you swap pairings via tweaks; **the canonical default is Inter + JetBrains Mono**.

- Body / UI: `'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif`
- Mono (SHAs, test names, computer names, log lines, numerical data): `'JetBrains Mono', 'Fira Code', ui-monospace, SFMono-Regular, Menlo, monospace`

Inter font-feature settings: `"cv11", "ss01", "ss03"` (alternate glyphs for `l`, `1`, `I` to disambiguate from SHAs).

**Sizes** (approximate, see source for precise values):
- Page headline (h1): 22–24px, weight 600, letter-spacing −0.2 to −0.3
- Card headings (h3): 13–14px, weight 600, uppercase 11px for sub-section headers
- Body: 13px
- Captions / labels: 11–12px
- Stat numbers (big): 22–28px, weight 600, letter-spacing −0.4

Numeric columns use `font-variant-numeric: tabular-nums` so things line up.

### Layout

Max content width: `--maxw 1320px`, centered. Nav height: `--nav-h 52px` (configurable for compact / roomy density).

---

## Theme handling

`<html data-theme="light|dark">` controls everything via CSS custom properties. The pre-load script in `prototype/index.html` reads `localStorage.mesa-theme` and applies before paint to avoid flash. Default is `system` (follows `prefers-color-scheme`). Toggle button cycles light → dark → system.

---

## Components inventory

Implement as proper components in your codebase, mapped to the prototype's atoms:

- `MesaMark` — the `M` from the wordmark, currentColor (favicon + nav)
- `CommitStatePill / BuildStatusPill / TestStatusPill` — colored chips with leading icon
- `StatusDot` — 8px circle
- `Sparkline` — see encoding above; SVG, configurable width/height, optional `current` highlight, optional `onPick` to navigate
- `SparklineLegend` — paired with sparkline
- `StatusMatrix` — the test×computer grid; key prop is `matrix` (output of `getMatrixForCommit`)
- `MatrixLegend`
- `CommitAvatar` — initials-on-color circle, deterministic color from author
- `Dropdown / DropdownItem` — generic popover. Click-outside closes.
- `CopyButton` — copies to clipboard, shows "Copied" for 1.5s
- `BranchPicker` — the inline branch chip. Two sizes (`lg` in page headline, `sm` in breadcrumb)
- `SearchInput` — icon-prefix input
- `SegmentedControl` — filter chip group with counts and optional dots
- `FlagChip` — small "FPE" / "Checksum ≠" / "Full inlists" labelled pill with icon
- `Icon` — single SVG component, names enumerated in `components.jsx`. Notable: `branch`, `commit`, `check`, `x`, `chevron`, `sun/moon`, `copy`, `github`, `plus`, `wrench`, `neq`, `clock`, `cpu`, `expand`, `eyeOff`.

Icons are 16x16 stroke-only with `stroke-width: 1.5`, `linecap: round`, `linejoin: round`. Inherit color via `currentColor`.

---

## Interactions & behavior

- **Navigation**: hash routing in the prototype. In production use whatever routing the codebase has. Routes are: list, commit detail, test on commit.
- **Branch switching**: changes branch in state; in production this would refetch commits for that branch. URL should encode branch.
- **Tab switching on commit detail**: default tab is computed from state (build issues → Computers, failures/mixed → Tests, otherwise Summary). Re-evaluate when navigating between commits. The user can override manually.
- **Banner action buttons**: jump to the relevant tab.
- **Matrix cell click**: navigates to test-on-commit view, passing the clicked computer as a focus hint (highlight that row in the table).
- **Column picker**: opens on click; closes on outside click. Selections persist (localStorage in production). Presets snap visibleCols to a known set.
- **CopyButton**: writes to clipboard; flash "Copied" pill for 1.5s.
- **Theme toggle**: cycles light → dark → system; updates `localStorage.mesa-theme` and `data-theme`. Pre-load script prevents flash.

### Hover states
- Commit row: background fades to `--bg-subtle` on hover
- Nav links: same
- Buttons: `--bg-muted` on hover for ghost; `--brand-hover` for primary
- Matrix cell: cursor pointer when click handler present; no visual hover by default (cells are small and dense; tooltip via native `title` is enough)

### Focus states
Use `--shadow-focus` (`0 0 0 3px var(--brand-ring)`) on focus-visible for buttons + inputs.

---

## State management (data layer)

Single derived helper does all the heavy lifting:

```js
const state = getCommitState(sha);
// → { build: { status, builtComputers, failedBuildComputers },
//     tests: { status, uniformFailingTests, mixedTests, pendingTests, hasUniformFail, hasMixed, hasPending, failingCells, mixedCells },
//     flags: { fpe, checksum, inlistsFull, flaggedCells },
//     ...flat-count convenience fields }
```

And the cell-level helper:
```js
const matrix = getMatrixForCommit(sha);
// → { [testId]: { [computerId]: { status, flags: { fpe, checksum, inlists_full } } } }
```

And for the test-on-commit view:
```js
const instances = getInstancesForTestOnCommit(sha, testId);
// → array of instance objects with all numerical columns
```

In production these would be backed by real DB queries / API calls. Cache aggressively — `getCommitState` is the right boundary to memoize.

---

## Demo scenarios (in mock data)

Use these to verify your implementation matches the design:

| sha | scenario |
| --- | --- |
| `aa27a08` | clean — all green |
| `7c4e2d1` | 4 uniform test failures + 2 full-inlist runs |
| `b81f9a3` | 1 failure + 1 FPE flag |
| `3d28c10` | 4 tests still running (pending demo) |
| `e91a5c2` | mixed test + partial build (only on rusty/popeye/frontera) |
| `2f74b08` | passing but 3 checksum mismatches — "two unique checksums" demo |
| `c5e8a01` | partial build + mixed (1.5M_with_diffusion) + uniform-fail (rotating_massive_star) + FPE |
| `d1f8a92` | total build fail — no test data |
| `8e7c1b3` | passing with full-inlist runs on derecho + expanse |

---

## Out of scope / known not-quite-right

- The screenshots were captured at ~914px wide. At that width the commits table headers compress and "Commit / SHA" labels nearly touch. At the design width (1320px) this is fine. Verify at full width.
- The "Test Instances" top-level page (the cross-commit list) is not designed in this pass. The current nav still references it but it's unimplemented.
- "Branches" and "Computers" top-level pages are nav-stubs only.
- Search ("⌘K") in the top nav is a visual mock — no actual command palette is wired up.
- Logs tab content is faked. In production it'd stream actual log files.

## Earlier exploration

Before settling on this direction, three visual studies were laid out side-by-side in a design canvas. Not included here (the user picked Direction A — modernized-GitHub — which is what this prototype implements), but mentioning for context: the alternatives were a scientific bento-grid (IBM Plex, larger numerals, watermarked logo) and a terminal/TUI take (Geist Mono, dark-first, ASCII status indicators). Some of their density / data-presentation ideas could still be useful in future iterations of dense panels.
