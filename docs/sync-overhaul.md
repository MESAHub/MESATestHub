# GitHub sync overhaul

This document captures the plan to replace the current `Branch.api_update_branches`
sync flow with a topology-driven one. The overhaul lands on its own branch
(working name: `perf-sync-topology`) and is expected to span multiple
sessions.

This is the follow-up to Phase 3, which moved sync off the webhook request
path with `BranchSyncJob` but did **not** reduce the underlying API-call
fan-out. That part is what this overhaul tackles.

## The problem

`Branch.api_update_branches` does roughly this for every push:

1. `api.branches(repo)` — list current branches (paginated).
2. For each branch whose head differs from the DB:
   - `branch.api_update` → `api.commits(sha: branch_name, per_page: 100)`,
     possibly up to 5 pages (500 commits) if no overlap with the DB is
     found.
   - For each commit returned: upsert it, fire
     `after_create :api_update_test_cases` if new, which makes one
     `api.content(...)` call per MESA module (currently 4).
   - Recompute `branch_memberships.position` by reverse-iterating the
     fetched window and writing positions via `upsert_all`.
3. Delete branches that no longer exist on GitHub.

The cost scales with **fetched window × modules**, not with **actual new
commits**. A push of one commit still triggers ~100 commits worth of
re-positioning and 4 content calls per new commit. A push of 50 new
commits across 5 modules triggers ~250 content calls.

The deeper issue, behind the API-call count, is that **`position` is not
a stable ordering** — it gets rewritten on every sync because the algorithm
recomputes it from whatever window of commits it happens to fetch. That's
why the algorithm has to fetch a wide window in the first place: it's
trying to establish enough context to assign positions consistently.

## The goal

**Commit ordering on each branch matches `github.com/MESAHub/mesa/commits/{branch}`.**

That target is concretely:

- **Reachability**: every commit reachable from the branch tip, walking
  *all* parent edges (not first-parent only). Merge commits and the
  commits they bring in are both included.
- **Order**: reverse chronological by `commit_time`.

This matches `git log <branch>` with default options and is the cheapest
of the plausible sort rules to compute from local state.

## The data model change

One new table:

```ruby
create_table :commit_relations do |t|
  t.bigint :parent_id, null: false
  t.bigint :child_id,  null: false
  # Optional: parent_index — only nonzero for merge commits; lets you
  # reconstruct first-parent walks if we ever need them.
end
add_index :commit_relations, [:child_id, :parent_id], unique: true
add_index :commit_relations, :parent_id
add_foreign_key :commit_relations, :commits, column: :parent_id
add_foreign_key :commit_relations, :commits, column: :child_id
```

Why a join table rather than columns on `commits`:

1. Merge commits have ≥ 2 parents (octopus merges can have more).
2. We need symmetric "parents of X" and "children of X" indexed lookups.
   "Next commit in the branch" walks toward children.
3. Per-edge metadata (e.g., parent index for first-parent reconstruction)
   has a natural home.
4. Matches the codebase's existing m:n style (`branch_memberships`,
   `test_case_commits`, `instance_inlists`).
5. Handles the "we know the SHA but not the metadata yet" case cleanly —
   we can hold a stub `commits` row and fill it in later without
   breaking FK semantics.

The `commit_relations` factory at
[`spec/factories/commit_relations.rb`](../spec/factories/commit_relations.rb)
already exists, suggesting someone (probably you) had this thought
previously.

`branch_memberships` stays — it's the cache for "which branches contain
this commit," and computing that from topology on every page render
would be expensive. The `position` column on it goes away.

## The new sync flow

For each push webhook:

1. **Identify what's new.** Read the payload's `commits[]` (which
   includes parent SHAs per commit). If the payload truncates (GitHub
   caps it at 20 commits per push), call
   `compare(before_sha, after_sha)` once for the explicit ordered list.
2. **Insert new edges.** For each new commit:
   - Upsert the `commits` row.
   - For each parent SHA: ensure a `commits` row exists (insert a stub
     if not), then insert into `commit_relations`. Already-present edges
     are no-ops (the unique index makes this idempotent).
3. **Move the branch pointer.** `branches.head_id = after_sha`'s commit
   id.
4. **Update `branch_memberships`.** Add `(branch, commit)` rows for
   every commit in the compare set. For merge commits, walk back via
   `commit_relations` to add memberships for any commits brought in
   from another branch that aren't already on this branch.
5. **Test cases.** If a new commit's `modified` / `added` list doesn't
   touch any `*/test_suite/do1_test_source` path, copy the parent's
   `TestCaseCommit` set instead of calling `api.content(...)`. This is
   orthogonal to the topology work but ships in the same phase since it
   shares the "use the webhook payload" theme.

Typical-push cost in the new flow: **zero API calls** (everything's in
the payload) or one (`compare`, when the payload truncates). Compared to
the current "fetch 100+ commits per branch + 4 content calls per new
commit."

## The new ordering query

The commits page for a branch becomes one recursive CTE:

```sql
WITH RECURSIVE reachable(id) AS (
  SELECT head_id FROM branches WHERE name = $1
  UNION
  SELECT cr.parent_id
    FROM commit_relations cr
    JOIN reachable ON cr.child_id = reachable.id
)
SELECT c.*
  FROM commits c
  JOIN reachable r ON c.id = r.id
  ORDER BY c.commit_time DESC
  LIMIT $2 OFFSET $3;
```

`UNION` (not `UNION ALL`) dedupes, which short-circuits traversal once
multiple merge paths converge on a shared ancestor. Postgres has
supported recursive CTEs since 8.4 (2009); this is standard SQL.

At MESA's scale (low thousands of commits per branch), this query runs
in single-digit milliseconds. If we ever sync a million-commit repo
we'd add depth-limiting tricks, but that's not on the horizon.

## Sequencing

Each step is its own commit (or small set of commits) on `perf-sync-topology`.

### Step 1 — Add `commit_relations`

Migration adding the table + indexes + FKs described above. No code
behavior changes. Drops nothing. Low-risk addition that the rest of the
work builds on.

### Step 2 — Backfill via paginated `api.commits`

A `BranchBackfillJob` per branch. Paginates `api.commits(sha: branch_name)`
(the endpoint already returns parent SHAs in every response — the current
code throws them away). Upserts edges from the parent SHAs into
`commit_relations`. Idempotent so it can be rerun.

Cost: low hundreds of API calls total across all of MESA's branches.
Probably 10–30 minutes wall-clock with light throttling. Well under the
5000 req/hour authenticated limit.

After this lands, the topology is populated and we can verify it makes
sense against a real branch (does the recursive CTE return the same
commits in the same order as GitHub.com?) before changing any
user-visible behavior.

### Step 3 — Rewrite the sync flow

`BranchSyncJob` (added in Phase 3) starts consuming the webhook payload
directly. New helpers on `Commit` to ingest a `commits[]` array,
record parent edges, and update branch memberships. Existing
`api_update_branches` and `Branch#api_update` get retired in this step
or in step 5, depending on how clean the cut comes out.

Add `compare(before, after)` as the fallback path for truncated
payloads. Single API call per push instead of N pages.

### Step 4 — Switch ordering to the recursive CTE

Update queries that read `branch_memberships.position`:

- [`app/models/branch.rb`](../app/models/branch.rb) — `nearby_commits`,
  `nearby_test_case_commits`, `api_reorder_*` (probably all delete-able
  by the end of this step)
- [`app/controllers/commits_controller.rb`](../app/controllers/commits_controller.rb)
  — `index` action's `@memberships = @branch.branch_memberships.where.not(position: nil).order(position: :desc)`
- Any view that reads `position` directly

Define `Branch#ordered_commits(limit:, offset:)` (or similar) backed by
the CTE. Have controllers call that.

### Step 5 — Drop the position column

Migration to remove `branch_memberships.position`. Delete the
renumbering code in `Branch#api_update`. Delete the dead
`api_update_tree` while we're in there (it's marked as unused in a
comment).

### Step 6 — Skip `api_update_test_cases` when source files unchanged

For each new commit, check the webhook payload's `modified` and `added`
lists for any path matching `*/test_suite/do1_test_source`. If none,
copy the parent commit's `TestCaseCommit` set instead of firing the
existing 4 module content calls.

This is orthogonal to the topology work — could ship before steps 4–5 if
we want a quicker partial win.

## Decisions already made

- **Match GitHub.com ordering** (reverse chrono over reachable set), not
  first-parent or topo-only. Easiest to compute, matches what users see
  on GitHub.
- **Join table, not array column.** Better querying, indexing, FK
  behavior, and matches the codebase pattern.
- **Clean cutover, not lazy hybrid.** Two code paths (old position-based,
  new topology-based) for any extended period is more operational cost
  than the few hundred backfill API calls saves.
- **Keep `branch_memberships`, drop `position`.** The "which branches
  contain commit X" question is still expensive to answer from raw
  topology; the table earns its keep as a cache.

## Open questions for when work begins

- Do we want `parent_index` on `commit_relations` from day one (lets us
  reconstruct first-parent walks for any future "branch's official
  history" view), or add it later if/when that view is wanted?
- Does the backfill job throttle itself, or do we just let it run as
  fast as the rate limit allows? `faraday-http-cache` is already wired
  in, so a lot of repeated calls will be 304s, but 304s still count
  against the limit.
- Inside step 3, should the new sync code live on `BranchSyncJob`
  directly, or do we factor out a `Sync::CommitGraph` service object?
  Lean toward keeping it on the job until we see what shape the code
  wants to take.
- Step 6's "copy parent TCCs" — what exactly do we copy? The
  `TestCaseCommit` rows pointing at the new commit, but with reset
  per-commit counters (status, submission_count, computer_count). Spec
  this carefully before implementing.

## Out of scope

- **Solid Queue.** ActiveJob's `:async` adapter is fine for the
  current load. Adopt Solid Queue if we want job deduplication or
  durability, but that's a separate decision.
- **GraphQL API.** The REST `commits` and `compare` endpoints give us
  everything we need; no reason to add GraphQL complexity.
- **Real-time updates beyond push events.** PR open/close/merge events
  can come later if they're worth ingesting at all.

## When this lands

Test suite is expected to grow with the work. The current 78-spec suite
will need at least:

- Model specs around `commit_relations` insertion via `Commit.ingest_payload`
  (or whatever the new entry point is called).
- A request spec asserting webhook push events drive the new flow without
  hitting `api.commits` at all (the existing webhook spec already proves
  the job indirection; this proves the inside-the-job behavior).
- An ordering spec asserting the recursive CTE returns commits in the
  same order GitHub.com does for a constructed scenario with a merge.
- A backfill job spec proving idempotence.

When all six steps are green, retiring `branch_memberships.position`
should be a small migration with confidence backed by the new specs.
