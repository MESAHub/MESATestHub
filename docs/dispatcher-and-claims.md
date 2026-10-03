# Dispatcher & claims

**Status:** Phases A and B merged (MESAHub/MESATestHub#97, #99, May
2026). Phase C (dispatcher endpoint) merged Oct 2026. Phase D (`mesa_test`
client) is next, shipping alongside per-computer API keys (roadmap
feature backlog). Claim sweeping runs as the `claim_sweep` Solid Queue
recurring task (`ClaimSweeperJob`, every 5 min — see
`config/recurring.yml`).

**Plan revised Oct 2026** before starting Phase C, to match what
Phases A/B actually shipped and what changed in the app since May.
The main corrections:

- Auth is the `submitter:` email/password block shared with the
  submissions API, not a per-computer `api_key`; request bodies nest
  under `submitter:` + `claim:` / `dispatch:`; test cases are named
  by `test_case_module` + `test_case_name`.
- "Has this configuration been run?" comes from `test_instances`
  (`run_optional`, `fpe_checks`, `resolution_factor`), which MESA has
  reported for years — not from the `submissions.use_*` columns,
  which only a claims-aware client will ever fill.
- The coverage term no longer subtracts one point per
  `test_instance` (a single computer submits ~100 per commit, so
  every tested commit floored at zero). Coverage now counts
  *computers*, and the dispatcher never re-recommends a commit the
  asking computer already submitted on — the rule the legacy
  `request_commit` endpoint always had.
- `scope: "test"` dispatch accepts the `commit_sha` the client just
  built. Without it the dispatcher could hand back a test on a
  commit the client never compiled.
- The legacy `GET /submissions/request_commit.json`
  (`Commit.test_candidate`) is now documented below. `mesa_test`
  1.2.0 doesn't call it.

This document is the design and implementation plan for two
intertwined features:

1. A **dispatcher** API that tells `mesa_test` clients which commit
   they should test next, instead of clients independently deciding.
2. A **claims** data model that records "computer X is testing
   commit Y" as a first-class object with a lifecycle, so the
   dispatcher can avoid recommending redundant work and the rest of
   the app can show a meaningful "pending" state.

A future, dependent feature — posting CI status back to GitHub —
gets its own doc once these two are in place. It needs the
"pending" semantics that claims unlock to be truthful.

## Motivation

Today, a workstation owner who wants to test commits has two bad
options: assume `main` needs testing (often wasteful — it might
already be covered) or eyeball the matrix to pick something. There's
no signal from the testhub about *what would actually be useful to
test next*, and no record of *who else is currently looking at this
commit*.

Three concrete problems fall out of this:

- **Redundant work.** Two computers can independently test the same
  SHA without knowing. Wasted cycles, especially on long-running
  full-inlists runs.
- **No pending state.** A commit with zero test_instances is
  indistinguishable from a commit that nobody's working on. The
  matrix shows the same blank cells either way.
- **CI flags in commit messages are advisory only.** `[ci optional]`,
  `[ci fpe]`, and `[ci converge]` are gentlemen's agreements
  with no enforcement and no targeting. `[ci skip]` is honored only
  by GitHub Actions; the testhub doesn't know about it.

The fix is two halves of one design:

- **A dispatcher** that knows what's been tested, what's currently
  claimed, what CI flags request, and recommends the next-best SHA
  for a given computer's capabilities.
- **A claims table** that records intent (computer X intends to test
  Y) separately from results (computer X submitted a passing
  test_instance for Y). Intent has a lifecycle: pending → fulfilled,
  pending → expired, and (importantly) expired → fulfilled when a
  late submission arrives.

## Concepts

### Claim

A claim is a record that **a specific computer has registered an
intent to do a specific piece of work**: either build a commit, or
run a single test case on a commit. Claims have a TTL; if no
submission arrives by `expires_at`, the claim transitions to
`expired` and the dispatcher considers the work abandoned.

A claim is *not* a binding contract. The computer can drop the work
silently; the claim just expires. Late submissions are still
accepted and reactivate the claim to `fulfilled`.

We deliberately picked "claim" over "commitment," "assignment,"
"reservation," etc. Reasons in chat history; the short version is:
zero collision with the heavily-used `Commit` model, accurate
semantics (the computer claims work; the testhub doesn't
binding-ly assign), and reads cleanly as both noun and verb.

### Dispatch vs. claim creation (two endpoints)

Two API actions, deliberately separate:

- **Dispatch** (`POST /api/v1/dispatch`) — a read-only recommendation.
  The testhub looks at what needs testing and returns a SHA plus
  flags. Does not write to the database. Computer can ignore the
  response.
- **Claim** (`POST /api/v1/claims`) — registers intent. Writes a
  row to `claims`. Sets the wall clock for expiration.

In the common case, `mesa_test` calls both back-to-back. The
separation matters because:

- **Restricted-network clusters** need the head node to claim on
  behalf of compute nodes, sometimes without doing a dispatch at
  all (the head node may have its own logic for picking SHAs).
- **Abandonment is free.** A dispatch that the client never claims
  doesn't pollute the database. No phantom claims to sweep.
- **Dispatch becomes inspectable.** A `--dry-run` flag in
  `mesa_test`, or an admin debug endpoint that asks "what would
  you recommend right now?", is trivial.

### CI message flags

The MESA convention uses these flags in commit messages:

- `[ci skip]` — this commit doesn't need testhub testing at all.
  GitHub Actions still does its own build check.
- `[ci optional]` — request that at least one computer run with
  all inlists (the full, slower test mode).
- `[ci fpe]` — request that at least one computer run with FPE
  checks on.
- `[ci converge]` — request that at least one computer run with
  the convergence-test environment variable set.

The latter three are *preferences*, not requirements. "At least
one" is the bar. The dispatcher honors these by:

1. Parsing the **first line** of the commit message at commit
   ingest time, storing as boolean columns on `Commit`. Only the
   first line counts — squash and merge commits routinely list
   every constituent commit's subject in their body, and a
   whole-message scan would falsely inherit every directive from
   every squashed commit. The MESA convention places directives
   in the subject line of the commit they apply to.
2. Boosting these commits' priority for **capable** computers
   (one that says it can do FPE gets `[ci fpe]` commits handed to
   it preferentially).
3. Tracking satisfaction: once a successful submission lands with
   the relevant flag, the boost decays. `[ci optional]` becomes a
   normal-priority commit once one computer has done a full-inlists
   run on it.

## Schema changes

### New table: `claims`

```ruby
create_table :claims do |t|
  t.references :computer, null: false, foreign_key: true
  t.references :commit, null: false, foreign_key: true
  # set when scope='test', null when scope='build'
  t.references :test_case_commit, foreign_key: true
  t.string :scope, null: false               # 'build' | 'test'
  t.string :status, null: false, default: 'pending'
                                              # 'pending' | 'fulfilled' | 'expired'
  t.boolean :use_fpe, default: false, null: false
  t.boolean :use_full_inlists, default: false, null: false
  t.boolean :use_converge, default: false, null: false
  t.datetime :dispatched_at                  # null if claim wasn't dispatcher-originated
  t.datetime :expires_at, null: false
  t.datetime :fulfilled_at                   # null until submission arrives
  t.timestamps
end

add_index :claims, [:commit_id, :status]
add_index :claims, [:computer_id, :status]
add_index :claims, [:test_case_commit_id, :status]
add_index :claims, :expires_at, where: "status = 'pending'"
```

Postgres check constraints enforce scope/FK coherence:

```sql
ALTER TABLE claims ADD CONSTRAINT claims_scope_fk_coherence CHECK (
  (scope = 'build' AND test_case_commit_id IS NULL) OR
  (scope = 'test'  AND test_case_commit_id IS NOT NULL)
);
```

`commit_id` is always populated (even for `scope='test'`, where
`test_case_commit.commit_id` would carry the same value) so that
"all claims on this SHA" is a single index lookup, not a join.
A model-level validation can assert
`test_case_commit.commit_id == commit_id` for test-scope claims.

### Additions to `commits`

```ruby
add_column :commits, :ci_skip, :boolean, default: false, null: false
add_column :commits, :wants_full_inlists, :boolean, default: false, null: false
add_column :commits, :wants_fpe, :boolean, default: false, null: false
add_column :commits, :wants_converge, :boolean, default: false, null: false
add_column :commits, :full_inlists_satisfied_at, :datetime
add_column :commits, :fpe_satisfied_at, :datetime
add_column :commits, :converge_satisfied_at, :datetime
```

The `wants_*` columns are populated at commit ingestion by parsing
the **first line** of the commit message (see the CI message flags
note above for why). The `*_satisfied_at` columns are refreshed by
a Submission `after_commit` callback when a submission with the
relevant flag arrives. Both pairs are read together by the
dispatcher's boost logic.

`ci_skip` is also set at ingestion. Skip commits are excluded from
the dispatcher entirely and (in the future GitHub status feature)
suppressed from posting any status.

### Additions to `submissions`

```ruby
add_reference :submissions, :claim, foreign_key: true     # nullable
add_column :submissions, :started_at, :datetime           # nullable
add_column :submissions, :use_fpe, :boolean, default: false, null: false
add_column :submissions, :use_full_inlists, :boolean, default: false, null: false
add_column :submissions, :use_converge, :boolean, default: false, null: false
```

- `claim_id` — nullable for backwards compat with old `mesa_test`
  versions that don't know about claims. Populated when the
  submission carries a `claim:` block with an `id`.
- `started_at` — when the actual work began, measured locally by
  the client. Used to disentangle queue delay from real runtime
  (see [Lifecycle](#lifecycle)). Nullable for compat; not
  required.
- `use_*` — what flags the client says it ran with. **Resolved in
  Phase C:** `test_instances` already carries `run_optional` and
  `fpe_checks` per run, straight from MESA's own test output, and
  every client fills them in today. Those columns, plus
  `resolution_factor` for converge, decide whether a request has been
  met. The `use_*` columns are informational only.

### TCC pre-existence

Test case commits are created at commit instantiation (the
existing topology sync infers the test case list from the parent
commit or refetches the manifest if files have changed). Claims
with `scope='test'` can therefore reference an existing TCC
directly — no find-or-create dance in the claim path. Since Sept
2026 a unique index on `(commit_id, test_case_id)` guarantees one
TCC per test per commit, so "the TCC for this test on this commit"
is unambiguous for both claims and dispatch.

## API surface

All three endpoints accept a per-computer API key in
`Authorization: Bearer …` ([`api-keys.md`](api-keys.md)). With a key,
the `submitter:` block is optional. They also still accept the legacy
`submitter:` hash with `email`, `password`, and `computer`: the
password is bcrypt-checked against the user, and the computer has to
belong to that user. Password failures return 422 with
`{ "error": ... }`, the same shape the submissions endpoint uses. An
unknown key returns 401. Because claims are per test, `/api/v1/` is
exempt from the generic per-IP throttles, like `/submissions`.

### `POST /api/v1/dispatch`

Read-only. Asks the testhub for a recommendation.

**Request:**

```json
{
  "submitter": { "email": "...", "password": "...", "computer": "tycho" },
  "dispatch": {
    "scope": "test",
    "commit_sha": "abc123...",
    "can_fpe": true,
    "can_full_inlists": true,
    "can_converge": false
  }
}
```

`scope` is what the client *wants* — `"build"` or `"test"`. A
client that wants the full `install_and_test` loop calls dispatch
with `scope: "build"`, gets a SHA, claims/builds/submits, then
loops on `scope: "test"` **passing that SHA as `commit_sha`** for
each test case, until it gets a 204.

`commit_sha` is only accepted with `scope: "test"` (422 for
build). With it, the dispatcher picks the next test on that commit.
Without it, the dispatcher only considers commits this computer has
already built: a commit where it has a submission whose `compiled`
isn't `false`.

`can_*` default to `false` when absent.

**Response (work available), 200:**

```json
{
  "commit_sha": "abc123...",
  "short_sha": "abc123d",
  "branch": "main",
  "scope": "test",
  "test_case_module": "binary",
  "test_case_name": "wd_planetary_companion",
  "flags": { "use_fpe": true, "use_full_inlists": false, "use_converge": false },
  "score": 23.4,
  "reasons": ["on main", "untested by any computer", "[ci fpe] not yet satisfied"],
  "dispatched_at": "2026-10-02T12:34:56Z",
  "target_url": "https://testhub.mesastar.org/main/commits/abc123d"
}
```

For `scope: "build"`, `test_case_module` / `test_case_name` are
`null`. `score` and `reasons` are for debugging and are not part of
the contract. They're there so `mesa_test request_work` (or a
curious human) can see *why* a commit was picked, which matters
while the coefficients get tuned.

**Response (nothing to do):** `204 No Content`. Lets the client
stay idle without burning a checkout on imaginary work.

**Errors:** 404 for an unknown `commit_sha`; 422 for a bad scope or
`commit_sha` with `scope: "build"`.

The dispatcher does not write to the database. `dispatched_at` is
returned for the client to echo back when it creates a claim.

### `POST /api/v1/claims`

Registers intent. Writes a `claims` row. (Shipped in Phase B.)

**Request:**

```json
{
  "submitter": { "email": "...", "password": "...", "computer": "tycho" },
  "claim": {
    "commit_sha": "abc123...",
    "scope": "test",
    "test_case_module": "binary",
    "test_case_name": "wd_planetary_companion",
    "use_fpe": false,
    "use_full_inlists": true,
    "use_converge": false,
    "dispatched_at": "2026-05-27T12:34:56Z"
  }
}
```

`test_case_module` + `test_case_name` are required for
`scope: "test"` and identify the TCC on the claimed commit (404 if
it doesn't exist — this endpoint never creates TCCs).

`dispatched_at` is optional. Echoed from a prior dispatch response;
omitted for head-node-on-behalf-of-compute-node claims that
bypassed dispatch entirely.

**Response (201):**

```json
{
  "claim_id": 8421,
  "expires_at": "2026-05-27T12:49:56Z"
}
```

**Claiming a whole suite:** `scope: "test", all_test_cases: true`
(with no test name) creates one claim per test on the commit in a
single request. It skips tests this computer already holds a pending
claim on, and responds with `{ "claim_ids": [...], "expires_at": ... }`.
`mesa_test install_and_test SHA` uses this, since it runs every test
in one go. Each test is still its own row, so the matrix shows them
pending individually.

The client writes `claim_id` to its local YAML (build YAML for
build claims, per-test YAML for test claims) so the eventual
submission can attach it.

### Updates to `POST /submissions/create`

Existing endpoint. New optional top-level block (shipped in Phase
B):

```json
"claim": { "id": 8421, "started_at": "...",
           "use_fpe": false, "use_full_inlists": true, "use_converge": false }
```

A submission with a claim `id` updates the matching claim to
`fulfilled` (or `expired → fulfilled` for late submissions). All
existing submission paths continue to work without it.

### Legacy `GET /submissions/request_commit.json`

An older "what should I test?" endpoint is still mounted.
`SubmissionsController#request_commit` calls `Commit.test_candidate`,
which returns the newest commit, checking main first, that this
computer hasn't submitted on, with `allow_optional` / `allow_fpe` /
`allow_skip` filters and a doubling `max_age` window. It knows
nothing about claims, coverage by other computers, or whether a
request has already been met. `mesa_test` 1.2.0 doesn't call it.
Leave it mounted until a claims-aware `mesa_test` is released, then
remove it along with `Commit.test_candidate`.

## Lifecycle

### Status transitions

```
                  fulfilling submission arrives
                  ┌───────────────────────────┐
                  ▼                           │
    [pending] ────── expires_at passes ──→ [expired]
        │                                      │
        └── submission arrives ──→ [fulfilled] ┘
                                  ▲
                                  │
                  late submission arrives
```

- **pending → fulfilled**: normal case. A submission arrives before
  `expires_at`. Claim's `fulfilled_at` is set.
- **pending → expired**: the sweeper finds a pending claim past
  `expires_at` and flips its status. No data arrived.
- **expired → fulfilled**: a late submission arrives. The claim
  flips back to `fulfilled` with `fulfilled_at` set. This is a
  legal and expected transition (think: build that took 70 min on
  a 1-hour TTL because of queue waiting).

### Fulfillment

`Submission#fulfill_claims` (`after_create_commit`) fulfills:

- the claim named by `claim_id`, if the submission sends one, and
- **every pending or expired claim this computer holds on this
  commit that the submission answers.** Build claims are answered by
  any submission: reporting a build, or test results, which imply a
  build. A test claim is answered by an instance of its test.

Matching (added in Phase D) means a client never has to keep track
of claim ids. A whole-suite `entire` submission fulfills the build
claim and every test claim in one go. Prior status isn't checked:
`pending` and `expired` both move to `fulfilled`.

### TTLs

V1: fixed values.

- **Build claims**: 1 hour. (Originally 15 minutes, raised in Phase D
  because a MESA build takes 10–40 minutes, longer with FPE checks.
  Most real builds would have expired before reporting.)
- **Test claims**: 12 hours.

These are wall clock from claim creation. They're deliberately
generous on the test side because some MESA tests legitimately
take hours, and short TTLs would cause noisy false expirations.

V2: smart TTL via `ClaimTTL.compute(computer:, test_case_commit:)`
returning seconds. Logic:

```ruby
recent = TestInstance.where(computer:, test_case:)
                     .order(created_at: :desc)
                     .limit(10)
if recent.size >= 5
  max_runtime = recent.maximum(:runtime_minutes) || 60
  (max_runtime * 1.5 + 15) * 60   # seconds, with 15-min buffer
else
  12.hours.to_i
end
```

Capped at 24h. Build claims stay fixed at 1 hour — no point in
historical regression for the easy case.

### Why claims are never deleted

A `claims` row is ~100 bytes including indexes. At realistic
activity (10 computers × 50 claims/day) that's 180K rows/year,
~18MB/year. The bulk-data tables (`test_data`, `inlist_data`,
`test_instances`) are several orders of magnitude larger. Claims
will never be the table you worry about.

Keeping them all gives:

- **FK integrity for submissions.** Submissions reference claims;
  if we deleted claims we'd lose the audit trail.
- **The expired → fulfilled transition.** Late submissions can
  retroactively reactivate the claim — only works if the row
  is still there.
- **Reliability scoring.** "What fraction of computer X's claims
  expire without submission?" needs history. Future-V2+ feature.
- **Smart-TTL feature.** Doesn't strictly need claim history (uses
  TestInstance) but having it doesn't hurt.

No sweeper needed beyond the `pending → expired` transition logic.
If pruning ever becomes warranted (it won't), the safe pattern is
delete-only-`expired`-with-no-submission older than 1 year.

### Why JIT claim creation is the recommended client default

The `claims.expires_at` clock starts when the row is written. If
the head node writes the claim before submitting to Slurm, the
claim may expire while queued, even though no actual work has
failed. JIT (create the claim as the first thing the test script
does) sidesteps this.

But JIT requires the compute node to talk to the testhub, which
isn't always possible. Hence `claim_strategy` is a `mesa_test`
config (see below), not a server policy. All strategies submit
`started_at`, which lets the server distinguish "queue delay" from
"real failure" regardless of when the claim was created.

### Dispatcher blocklist

A computer that lets a claim expire **without ever submitting** is
the only signal that strongly suggests real trouble. Such claims are
blocklisted from re-dispatch to that computer. An abandoned **build**
claim blocks the whole commit. An abandoned **test** claim blocks only
that test, because one hung test shouldn't take the rest of the
commit's tests off the table.

```ruby
# WorkDispatcher#blocklisted_claims
Claim.expired.where(computer: c).where.missing(:submission)
```

`expired → fulfilled` transitions automatically remove the pair
from the blocklist, because the late-arrived submission satisfies
`where.missing(:submission)` being false.

## Recommendation algorithm

### Configurations

The matrix (`CommitState#matrix_columns`) already splits a
computer's runs into comparison pools by how they were run:
default vs. full inlists (`run_optional`), and FPE checks on
(`fpe_checks`). Toolchain (SDK vs. not) is the computer's own
property, not something the dispatcher can ask for. The dispatcher
uses the same two run-time switches plus converge. A CI request is
met for a test once *any* computer has a result for it with that
switch on, whatever the outcome. A failing full-inlists run still
answers "did anyone try this with full inlists?" (this resolves
open question 4).

| Request | Met for a test when a run of it has… |
|---|---|
| `[ci optional]` | `test_instances.run_optional = true` |
| `[ci fpe]` | `test_instances.fpe_checks = true` |
| `[ci converge]` | `test_instances.resolution_factor ≠ 1` |

These are the env vars MESA's `each_test_run` reads and echoes into
each test's `testhub.yml`:

- **Full inlists:** `MESA_SKIP_OPTIONAL` *unset*. Optional inlists
  run by default; most clients set the variable to skip them.
- **FPE:** `MESA_FPE_CHECKS_ON=1`. This is **build-time** as well:
  `make/defaults-module.mk` turns on `WITH_FPE_CHECKS`, so an FPE run
  needs an FPE build. A test-scope `can_fpe` therefore means "the
  build I'm testing was compiled with FPE checks". The client chooses
  FPE when it builds, and every test of that build runs with it.
- **Converge:** `MESA_TEST_SUITE_RESOLUTION_FACTOR` set to a factor.
  Past `[ci converge]` runs used 0.5–0.9; 484 of the 485 instances
  with a factor other than 1 sit on `[ci converge]` commits.

At the commit level, `commits.<x>_satisfied_at` is set the first
time a **single computer** has covered **every** TCC on the commit
in that configuration. A full-inlists run of one test doesn't
answer "run this commit with optional inlists." A Submission
`after_create_commit` callback refreshes it via
`Commit#refresh_ci_satisfaction!`, which is a no-op when the commit
has no `wants_*` flags. Columns are only ever set, never cleared.
A rake task, `claims:backfill_satisfaction`, fills them in for
commits flagged before Phase C. It stamps the time it runs, not the
time the coverage actually happened. Against the Sept 2026 snapshot
it checks 939 flagged commits in about 2 s.

### Candidate commits (both scopes)

- `commit_time` within the last 30 days.
- On an **active branch**: `main`, or an unmerged branch whose head
  commit is less than 90 days old.
- `ci_skip = false`.
- Not blocklisted for this computer (an expired build claim on the
  commit that never got a submission; see
  [Dispatcher blocklist](#dispatcher-blocklist)).

### Build scope

Also exclude commits where this computer already has a submission
or a pending build claim. Re-recommending a commit it already
tested is never useful.

Score each remaining commit:

```
score =
  branch           (10 if on main, else 5)
+ recency          (10 × (1 − age_days / 30), floor 0)
− coverage         (5 for the first distinct other computer that has
                    submitted on the commit or holds a pending build
                    claim on it, 2 for each one after)
+ ci boosts        (+5 for each wants_x that is unsatisfied and that
                    this computer can do: fpe, full_inlists, converge)
```

Ties go to the newer `commit_time`, then the SHA. The top scorer is
returned with `use_x = wants_x && !x_satisfied && can_x`.

The coverage penalty shrinks after the first computer on purpose
(decided Oct 2026). We want at least two computers on every main
commit, since checksum comparison needs a second opinion. A
once-covered fresh main commit (10 + 10 − 5 = 15) beats an untested
6-day-old feature commit (5 + 8 = 13). A second computer costs only 2
more, so main commits keep attracting extra platforms while they're
recent.

### Test scope

Pick the commit: the given `commit_sha`, or else the best-scoring
candidate commit this computer has built in the last 7 days (same
score, minus the "already submitted" exclusion). If the chosen commit has no eligible
TCC, move on to the next commit. A pinned `commit_sha` that has none
returns 204.

On that commit, for each TCC, work out the configurations it still
needs. `full` is needed when the commit `wants_full_inlists`, the
computer `can_full_inlists`, and no run of this TCC has
`run_optional` and no pending claim on it has `use_full_inlists`.
`fpe` and `converge` work the same way. A TCC is **eligible** if:

- this computer has no pending test claim on it and no abandoned
  test claim on it, **and**
- this computer hasn't run it yet, **or** it still needs one of the
  configurations above.

Rank eligible TCCs by:

1. most needed configurations first,
2. then fewest computers covering it (`computer_count` plus
   distinct computers with pending claims),
3. then module and name, so the order is stable.

Return the top one. Its `flags` carry FPE, if needed (a property of
the whole build, so it costs nothing extra), plus **at most one**
run-time mode. A full-inlists run at a converge resolution factor
answers neither request cleanly, and checksum comparison excludes it,
so a test that needs both gets two runs on successive dispatches
(found in the Phase D end-to-end run).

Coefficients are placeholders. Tune them once real dispatch traffic
exists. Don't over-engineer V1.

### Real-world load (Oct 2026 snapshot)

About 210 commits in a 60-day window, 38 active non-main branches.
Most commits have one computer (`LLNL_Dane` covers ~80%), and every
active client sends an `empty` build submission followed by
one-result-per-test submissions. That matches the build → test
dispatch loop above. At that size, scoring in Ruby over a few
batched queries is fine; no SQL-side scoring needed. Measured on that
snapshot: build dispatch takes 15–50 ms, test dispatch 15–175 ms.

Unpinned test dispatch used to go back to old commits where the
computer had built but skipped a few tests (delorean got a 25-day-old
main commit). It now only looks at builds from the last 7 days
(`WorkDispatcher::RECENT_BUILD_WINDOW`). A pinned `commit_sha`, which
is what `install_and_test best` sends, isn't affected.

### Race conditions

Two computers dispatch simultaneously and may receive the same
SHA. This is acceptable — multiple computers testing the same SHA
isn't wrong, it's coverage. The next request from either computer
will re-evaluate and find a different best candidate (the SHA's
coverage_weight will have increased due to the new pending claim).

No `SELECT FOR UPDATE` needed in V1. If duplication ever becomes
operationally annoying, add it.

## `mesa_test` client changes

Out of scope for this repo, but the contract needs writing down
here so the client work has a clear spec. The following changes to
`mesa_test` are required for the V1 feature to work end-to-end:

### New subcommand: `mesa_test request_work`

Wraps `POST /dispatch`. Prints the recommendation as JSON, or
exits 0 with no output on 204 (no work). Useful for scripting and
debugging.

### Modified subcommands

- `mesa_test install [SHA|best] [--no-claim]` — `best` calls
  dispatch (scope=build) first. With or without `best`, the
  install path then creates a build claim and writes `claim_id`
  to the build YAML. `--no-claim` skips claim creation (for
  weird-network cases where the head node has already claimed).
- `mesa_test test TEST [--no-claim]` — creates a test claim
  before running. Writes `claim_id` to the test's YAML. Same
  `--no-claim` escape hatch.
- `mesa_test install_and_test [SHA|best]` — runs install then
  loops over tests serially. Each test goes through its own
  claim cycle. (Reuse of `mesa_test test` internally avoids the
  client-side "intent for all tests" concept entirely.) With
  `best`, the loop asks `scope: "test"` dispatch, pinned to the
  installed SHA via `commit_sha`, for the next test until it gets a
  204; that's how CI-requested configurations reach the right
  tests.

### New config: `claim_strategy`

Persisted in the per-computer YAML. Values:

- **`jit`** (default for workstations and clusters with open
  networking) — the build/test script creates its own claim
  immediately before doing work. Wall clock matches real work
  time; queue delay isn't a factor.
- **`pre_queue`** (for restricted-network clusters) — the head
  node creates the claim before submitting the job to Slurm.
  Claims may expire while queued; `started_at` on the eventual
  submission lets the server tell the difference.
- **`on_run`** (optional, for those willing to poll Slurm) — the
  head node watches scheduler state and creates the claim when
  the job transitions to RUNNING. Best of both worlds at the
  cost of polling complexity.

### Submission payload additions

All submissions (build and test) gain an optional `claim:` block
(see [Updates to `POST /submissions/create`](#updates-to-post-submissionscreate)):

- `id` — the integer from the claim response.
- `started_at` — when the actual work began. ISO 8601.
- `use_fpe`, `use_full_inlists`, `use_converge` — the actual
  flags the work ran with.

Backwards compatibility: old `mesa_test` versions that don't send
these continue to work. The testhub treats their submissions as
"unclaimed" — they don't satisfy any claim, but they still create
the test_instance records they always did, and those records'
`run_optional` / `fpe_checks` still count toward CI-request
satisfaction.

### Capabilities reporting

Each computer reports its capabilities inside the `dispatch:` block
of every dispatch request (`can_fpe`, `can_full_inlists`,
`can_converge`). Absent means `false`.

For now, these are configured per-computer in the local YAML. The
testhub may eventually want to persist them server-side, but V1
trusts the client.

## Implementation sequencing

Implementation is intended to happen across multiple sessions. Each
phase is independently shippable to `master` (with sensible no-op
behavior until the next phase wires it in). Land each phase as its
own PR off this feature branch — or, if scope grows, off
phase-specific branches off `master`.

### Phase A: Schema & CI flag parsing — ✅ merged (MESAHub/MESATestHub#97)

Migration for `claims` plus the `commits` / `submissions` columns;
`Claim` model; `CommitMessageFlags.parse` (first line only), called
from both commit-ingest paths. The `Commit#ci_*?` predicates now
read the stored columns.

### Phase B: Claim creation endpoint + sweeper — ✅ merged (MESAHub/MESATestHub#99)

- `POST /api/v1/claims` (`Api::V1::ClaimsController`), with
  `submitter:` auth as in the submissions API.
- `Claim.sweep_expired!`, run every 5 minutes by `ClaimSweeperJob`
  (Solid Queue recurring task `claim_sweep`); `rake claims:sweep`
  for manual runs.
- Fixed TTLs: `Claim::TTL_FOR_SCOPE` (15 min build — raised to 1 h in Phase D — and 12 h test).
- Submissions accept `claim: { id, started_at, use_* }`;
  `Submission#fulfill_claim` (`after_create_commit`) moves the claim
  from pending or expired to fulfilled.
- Also shipped: claims became the "pending" signal. `CommitState`
  splits `:pending` from `:not_run` on `has_pending_claims?`, and
  `TestCaseCommit#pending?` requires an open claim.

### Phase C: Dispatcher endpoint

**Branch:** `feature-dispatcher-endpoint`
**Estimate:** 1–2 days
**Goal:** A working dispatcher with the V1 algorithm.

- `POST /api/v1/dispatch` (`Api::V1::DispatchController`).
  Read-only. Auth is shared with the claims controller through a
  small `ApiSubmitterAuth` concern.
- `WorkDispatcher` service. Inputs: computer, scope, optional pinned
  commit, capabilities. Output: a `WorkDispatcher::Recommendation`
  (commit, TCC, flags, score, reasons) or `nil` (→ 204).
- Algorithm as specified in
  [Recommendation algorithm](#recommendation-algorithm).
- Satisfaction tracking: `Commit#refresh_ci_satisfaction!` from a
  Submission `after_create_commit` callback, plus the
  `claims:backfill_satisfaction` rake task.
- Specs: about 10 dispatcher scenarios — a new commit on main beats
  an old feature commit; commits already covered by other computers
  score lower; skips commits this computer submitted on; blocklisted
  commit; `ci_skip`; inactive or merged branch; nothing to do → nil;
  FPE boost only for capable computers; test scope picks
  uncovered TCCs and skips claimed ones; pinned `commit_sha`. Plus
  request specs for auth, 204, 404, 422, and model specs for
  satisfaction.

**Done means:** the full V1 contract is implementable by
`mesa_test`. Internally, a client could call
`/dispatch` → `/claims` → run work → `/submissions` and the system
behaves correctly.

### Phase D: `mesa_test` client work

**Repos:** `MESAHub/mesa_test` (client, branch `feature-claims-client`)
plus a small testhub PR (`feature-claims-client-support`).
**Goal:** Real-world end-to-end usability.

**Testhub side (Oct 2026):**
- Claims are fulfilled by matching computer, commit, and test, so the
  client never tracks claim ids (see [Fulfillment](#fulfillment)).
- `all_test_cases: true` claims a whole suite in one request.
- Converge satisfaction reads `resolution_factor`.
- The build TTL goes from 15 minutes to 1 hour.

**Client side:** see [`mesa_test` client changes](#mesa_test-client-changes).
Two simplifications from the original sketch:
- Because fulfillment is by matching, the client keeps no claim-id
  state on disk, and `claim_strategy` isn't needed for V1.
- `install_and_test SHA` keeps its whole-suite behavior, plus a
  build claim and an all-tests claim. `install_and_test best` is the
  new dispatch-driven loop: build dispatch → claim → install → submit
  the build → per-test dispatch pinned to the SHA → claim → run →
  submit, until a 204.

### Phase E (V2+): Smart TTLs

**Branch:** `feature-smart-claim-ttls`
**Estimate:** 0.5 days
**Goal:** Test claims use historical runtime to pick TTL.

- `ClaimTTL.compute(computer:, test_case_commit:)` service.
  Logic in [TTLs](#ttls) section.
- Used from the claims controller. Build TTL stays fixed.

### Phase F (V2+): GitHub status integration

**Doc:** TBD — separate doc once Phases A–C land.
**Goal:** Post commit statuses to GitHub reflecting testhub state.

Outline from prior planning conversation:

- Use the Commit Statuses API (not Checks API). Existing
  `GIT_TOKEN` plus `repo:status` scope.
- Map commit state → GH state. Pending iff there are pending
  claims and no contradicting submission. Success iff all
  submissions pass and coverage targets met. Failure iff any
  failure.
- `[ci skip]` commits: post nothing.
- Description includes in-flight context ("still being tested by
  tycho").
- Job: `GithubStatusJob`. Triggered from Submission and Claim
  callbacks. Env-gated to production.

### Phase G (V2+): Reliability scoring

**Branch:** `feature-claim-reliability-scoring`
**Estimate:** 0.5 days
**Goal:** Dispatcher deprioritizes chronically-unreliable computers.

- Compute per-computer expiration rate over the last N claims.
- Subtract from dispatcher score (proportional, not binary).
- Surface in computer admin view.

## Things deliberately out of scope (for V1)

- **Per-test-case capability matching beyond the three boolean
  flags.** If specific test cases need specific hardware (large
  RAM, particular compilers), that's a future feature. V1 trusts
  that any capable computer can run any test.
- **Coverage targets per branch.** V1 uses a flat
  "fewer-test-instances = higher priority" heuristic. No
  configurable "main needs 3 computers, feature branches need 1."
- **Multi-SHA dispatch responses.** One SHA per request. Clients
  that want more call again.
- **Long-polling, push, or any non-poll dispatch mechanism.**
  `mesa_test` is manually invoked or cluster-cron-driven. Polling
  every 10–15 minutes is the actual usage pattern.
- **Persistent computer capability storage server-side.** Clients
  declare capabilities each request.
- **An admin UI for browsing claims.** The data is there; building
  UI on top can wait until there's a known need.
- **Backfilling claims for historical commits.** New behavior
  starts from the deploy date.

## Open questions to resolve during implementation

These don't block the plan but need decisions when the relevant
code gets written. Listed here so they don't get lost.

1. ~~**`use_fpe` etc. on Submission vs. TestInstance.**~~
   **Resolved (Phase C/D):** decided by `test_instances.run_optional`
   / `fpe_checks` / `resolution_factor`, which every client already
   sends. `Submission#use_*` is informational. See
   [Configurations](#configurations).
2. **Late-fulfillment status distinction.** Currently planned: just
   `fulfilled`, no distinction between "fulfilled on time" and
   "fulfilled late." Derivable from `fulfilled_at - expires_at`.
   Revisit if querying "how often do we run over?" becomes a
   recurring need.
3. **Branch importance config.** Main = 10, others = 5 is a
   placeholder. May want a `branches.dispatch_weight` column if
   different branches need different priorities (e.g., release
   branches > feature branches > experimental).
4. ~~**CI flag satisfaction granularity.**~~ **Resolved (Phase C):**
   any run counts, pass or fail; at the commit level one computer
   has to cover every test in that configuration. See
   [Configurations](#configurations).
5. **Dispatch token / replay protection.** Currently planned: no
   signing, just trust the `dispatched_at` echo. If abuse becomes
   a concern (it won't at this scale), add HMAC signing.
6. **Should dispatch favor branch heads?** V1 treats every commit
   on an active branch alike apart from recency. If clients keep
   getting sent to mid-branch commits that nobody will look at,
   add a head bonus.

## Related docs

- [`roadmap.md`](roadmap.md) — overall modernization history; this
  doc is the first major post-migration feature.
- (Future) `docs/github-status.md` — the GitHub CI status feature
  that this work unblocks.
