# Dispatcher & claims

**Status:** planning. Not yet implemented.
**Branch when implementation starts:** `feature-dispatcher-and-claims`
(this doc) → per-phase branches (`feature-claims-schema`,
`feature-dispatcher-endpoint`, etc.) as work proceeds.

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
  submission carries a `claim_id` in its payload.
- `started_at` — when the actual work began, measured locally by
  the client. Used to disentangle queue delay from real runtime
  (see [Lifecycle](#lifecycle)). Nullable for compat; not
  required.
- `use_*` — what flags this submission was run with. Needed to
  determine whether the submission satisfies a `wants_*` preference
  on the commit. Existing tracking on `TestInstance` may already
  cover some of this; verify during implementation and dedupe if
  so.

### TCC pre-existence

Test case commits are created at commit instantiation (the
existing topology sync infers the test case list from the parent
commit or refetches the manifest if files have changed). Claims
with `scope='test'` can therefore reference an existing TCC
directly — no find-or-create dance in the claim path.

## API surface

### `POST /api/v1/dispatch`

Read-only. Asks the testhub for a recommendation.

**Request:**

```json
{
  "computer": "tycho",
  "api_key": "...",
  "capabilities": {
    "can_fpe": true,
    "can_full_inlists": true,
    "can_converge": true,
    "scope": "test"
  }
}
```

`scope` is what the client *wants* — `"build"` or `"test"`. A
client that wants the full `install_and_test` loop calls dispatch
with `scope: "build"`, gets a SHA, claims/builds/submits, then
loops on `scope: "test"` for each test case.

**Response (work available):**

```json
{
  "commit_sha": "abc123...",
  "branch": "main",
  "scope": "build",
  "test_case": null,
  "flags": {
    "use_fpe": false,
    "use_full_inlists": true,
    "use_converge": false
  },
  "dispatched_at": "2026-05-27T12:34:56Z",
  "target_url": "https://testhub.mesastar.org/commits/abc123..."
}
```

Or for `scope: "test"`:

```json
{
  "commit_sha": "abc123...",
  "branch": "main",
  "scope": "test",
  "test_case": "twin_studies/binary_basic",
  "flags": { "use_fpe": true, "use_full_inlists": false, "use_converge": false },
  "dispatched_at": "2026-05-27T12:34:56Z",
  "target_url": "https://testhub.mesastar.org/commits/abc123..."
}
```

**Response (nothing to do):** `204 No Content`. Lets the client
stay idle without burning a checkout on imaginary work.

The dispatcher does not write to the database. `dispatched_at` is
returned for the client to echo back when it creates a claim.

### `POST /api/v1/claims`

Registers intent. Writes a `claims` row.

**Request:**

```json
{
  "computer": "tycho",
  "api_key": "...",
  "commit_sha": "abc123...",
  "scope": "build",
  "test_case": null,
  "use_fpe": false,
  "use_full_inlists": true,
  "use_converge": false,
  "dispatched_at": "2026-05-27T12:34:56Z"
}
```

For `scope: "test"`, `test_case` is the test case name. The server
looks up the matching TCC.

`dispatched_at` is optional. Echoed from a prior dispatch response;
omitted for head-node-on-behalf-of-compute-node claims that
bypassed dispatch entirely.

**Response:**

```json
{
  "claim_id": 8421,
  "expires_at": "2026-05-27T12:49:56Z"
}
```

The client writes `claim_id` to its local YAML (build YAML for
build claims, per-test YAML for test claims) so the eventual
submission can attach it.

### Updates to `POST /submissions/create`

Existing endpoint. New optional fields in the payload:

- `claim_id` — the integer returned from claim creation.
- `started_at` — ISO 8601 timestamp from the client.
- `use_fpe`, `use_full_inlists`, `use_converge` — flags this
  submission was run with.

A submission with a `claim_id` updates the matching claim to
`fulfilled` (or `expired → fulfilled` for late submissions). All
existing submission paths continue to work without claim_id.

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
  legal and expected transition (think: build that took 20 min on
  a 15-min TTL because of queue waiting).

The transition is implemented in the `Submission` callback that
fires on create: look up the claim, set `fulfilled_at`, set
`status = 'fulfilled'`. Don't check the prior status — both
`pending` and `expired` move to `fulfilled` on submission arrival.

### TTLs

V1: fixed values.

- **Build claims**: 15 minutes.
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

Capped at 24h. Build claims stay fixed at 15 min — no point in
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
the only signal that strongly suggests real trouble. Those
(computer, commit) pairs are blocklisted from re-dispatch:

```ruby
# In the dispatcher's candidate filter:
Claim.where(computer: c, commit: cmt, status: :expired)
     .where.missing(:submission)
     .exists?   # if true, skip this candidate
```

`expired → fulfilled` transitions automatically remove the pair
from the blocklist, because the late-arrived submission satisfies
`where.missing(:submission)` being false.

## Recommendation algorithm

### Priority ladder (V1)

For a `POST /dispatch` request with the requested scope and
capabilities:

1. **Filter out**:
   - `commits.ci_skip = true`
   - commits older than 30 days (configurable cap; prevents stale
     backlog from dominating)
   - commits where this computer has any expired-without-submission
     claim (the blocklist)
   - commits not on any "active" branch (V1 definition: branch has
     a commit in the last 90 days. Configurable later.)

2. **Score remaining commits** by weighted sum:

   ```
   score =
     branch_weight    (main = 10, others = 5)
   + recency_weight   (newest = 10, decays linearly over 30 days)
   + coverage_weight  (each existing test_instance subtracts 1;
                       each pending claim subtracts 1; floor at 0)
   + fpe_boost        (+5 if commit.wants_fpe and not satisfied
                       and computer.can_fpe)
   + inlists_boost    (+5 if wants_full_inlists and not satisfied
                       and computer.can_full_inlists)
   + converge_boost   (+5 if wants_converge and not satisfied
                       and computer.can_converge)
   ```

3. **Return the top scorer**, with `flags` set to:
   - `use_full_inlists: true` if commit.wants_full_inlists and
     not yet satisfied and the computer is capable; otherwise
     `false` (the default — most submissions run partial inlists).
   - Same pattern for `use_fpe` and `use_converge`.

4. **For `scope: "test"`**: also pick a specific TCC from the
   chosen commit. Prefer TCCs with the fewest test_instances and
   fewest pending claims. Ties broken by test case name (stable
   order).

Coefficients above are placeholders. They will need tuning once
real dispatch traffic exists. Don't over-engineer V1.

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
  client-side "intent for all tests" concept entirely.)

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

All submissions (build and test) gain three new optional fields:

- `claim_id` — the integer from the claim response.
- `started_at` — when the actual work began. ISO 8601.
- `use_fpe`, `use_full_inlists`, `use_converge` — the actual
  flags the work ran with.

Backwards compatibility: old `mesa_test` versions that don't send
these continue to work. The testhub treats their submissions as
"unclaimed" — they don't satisfy any claim, but they still create
the test_instance records they always did.

### Capabilities reporting

Each computer reports its capabilities in dispatch and claim
requests:

```json
{
  "can_fpe": true,
  "can_full_inlists": true,
  "can_converge": false
}
```

For now, these are configured per-computer in the local YAML. The
testhub may eventually want to persist them server-side, but V1
trusts the client.

## Implementation sequencing

Implementation is intended to happen across multiple sessions. Each
phase is independently shippable to `master` (with sensible no-op
behavior until the next phase wires it in). Land each phase as its
own PR off this feature branch — or, if scope grows, off
phase-specific branches off `master`.

### Phase A: Schema & CI flag parsing

**Branch:** `feature-claims-schema`
**Estimate:** 0.5 days
**Goal:** Get the schema in and the easy data ingestion working.
No API endpoints yet.

- Migration creating `claims`, the `Commit` boolean columns, the
  `Submission` columns. Indexes per spec above.
- `Claim` model with the basic associations, status/scope enums,
  and validation that `commit_id == test_case_commit.commit_id`
  for test scope.
- Commit message parser. New module
  `CommitMessageFlags.parse(message)` scans only the **first
  line** of the message and returns the four booleans. Called
  from the commit ingest path (`BranchSyncJob`-adjacent —
  check the actual ingest method during implementation).
- Specs: `Claim` validation matrix; `CommitMessageFlags` parser
  cases (all four flags, none, multiple, weird whitespace).

**Done means:** schema migrated, new commits get their `ci_*` /
`wants_*` columns populated automatically, no behavior change for
users. The dispatcher and claim endpoints don't exist yet.

### Phase B: Claim creation endpoint + sweeper

**Branch:** `feature-claim-endpoint`
**Estimate:** 1 day
**Goal:** Claims can be created and expire correctly.

- `POST /api/v1/claims` controller and routing. Authentication via
  the existing `Computer`/`api_key` mechanism (mirror
  `SubmissionsController`).
- `ClaimSweeper` (recurring job or rake task) that flips
  `pending` claims past `expires_at` to `expired`. Cadence:
  every 5 minutes is fine; this is cheap.
- Fixed TTLs for V1: 15 min build, 12 hours test. Constants on the
  `Claim` model, no per-computer or per-test logic yet.
- Submission integration: extend submissions API to accept
  `claim_id` and `started_at`. Update the matching claim's
  `fulfilled_at` and `status` on submission create. Handle both
  pending → fulfilled and expired → fulfilled transitions.
- Specs: claim create endpoint (happy, bad scope, missing TCC,
  unauthenticated); sweeper transitions pending → expired;
  submission with `claim_id` fulfills a pending claim; submission
  with `claim_id` fulfills an expired claim.

**Done means:** clients can create claims and they're tracked
correctly through their full lifecycle. Dispatch endpoint doesn't
exist yet — `mesa_test` couldn't actually use this without one,
but the data model is correct.

### Phase C: Dispatcher endpoint

**Branch:** `feature-dispatcher-endpoint`
**Estimate:** 1–2 days
**Goal:** A working dispatcher with the V1 algorithm.

- `POST /api/v1/dispatch` controller. Read-only.
- `WorkDispatcher` service object. Inputs: computer,
  capabilities, requested scope. Output: a recommendation
  (commit/scope/test_case/flags) or `nil` (→ 204).
- V1 algorithm exactly as specified in the
  [Recommendation algorithm](#recommendation-algorithm) section.
  No bells, no smart TTLs, no reliability scoring.
- Satisfaction tracking: Submission callback updates the
  `wants_*_satisfied_at` columns on Commit when a submission
  arrives with the relevant `use_*` flag.
- Specs: dispatcher returns sensible candidates for common
  scenarios (new commit on main, commit with partial coverage,
  blocklisted commit, ci_skip commit, no candidates → 204,
  capability mismatch on FPE, etc.). Aim for ~10 dispatcher
  scenario specs; this is the core decision logic.

**Done means:** the full V1 contract is implementable by
`mesa_test`. Internally, a client could call
`/dispatch` → `/claims` → run work → `/submissions` and the system
behaves correctly.

### Phase D: `mesa_test` client work

**Repo:** [`MESAHub/mesa_test`](https://github.com/MESAHub/mesa_test)
(separate repo; out of scope for this branch)
**Estimate:** unknown — depends on existing client structure.
**Goal:** Real-world end-to-end usability.

Covered in [`mesa_test` client changes](#mesa_test-client-changes)
above. Plan and track separately.

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

1. **`use_fpe` etc. on Submission vs. TestInstance.** The submission
   tracks the run-wide flags; TestInstance may already track
   per-test flags (`run_optional`, `fpe_checks` appear in the
   morning mailer cohort key). Confirm during Phase A and dedupe.
   May need only TestInstance-level columns and derive submission
   defaults from them.
2. **Late-fulfillment status distinction.** Currently planned: just
   `fulfilled`, no distinction between "fulfilled on time" and
   "fulfilled late." Derivable from `fulfilled_at - expires_at`.
   Revisit if querying "how often do we run over?" becomes a
   recurring need.
3. **Branch importance config.** Main = 10, others = 5 is a
   placeholder. May want a `branches.dispatch_weight` column if
   different branches need different priorities (e.g., release
   branches > feature branches > experimental).
4. **CI flag satisfaction granularity.** `[ci optional]` is
   satisfied once one computer runs with `use_full_inlists`.
   Should it require a *passing* run, or does any run count?
   Strawman: any non-error submission counts (a failure with full
   inlists still answers the question of "did anyone try this with
   full inlists?"). Revisit if it produces surprising behavior.
5. **Dispatch token / replay protection.** Currently planned: no
   signing, just trust the `dispatched_at` echo. If abuse becomes
   a concern (it won't at this scale), add HMAC signing.

## Related docs

- [`roadmap.md`](roadmap.md) — overall modernization history; this
  doc is the first major post-migration feature.
- (Future) `docs/github-status.md` — the GitHub CI status feature
  that this work unblocks.
