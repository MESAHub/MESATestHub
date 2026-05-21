class Branch < ApplicationRecord
  belongs_to :head, class_name: 'Commit', optional: true

  has_many :branch_memberships, dependent: :destroy
  has_many :commits, through: :branch_memberships
  has_many :test_case_commits, through: :commits

  scope :merged, -> { where(merged: true) }
  scope :unmerged, -> { where(merged: false) }

  ZERO_SHA = '0' * 40

  ###################################
  # PHASE 3.5 ORDERING (RECURSIVE)  #
  ###################################
  #
  # Ordering comes from a recursive CTE walking commit_relations
  # back from this branch's head. UNION (not UNION ALL) dedupes,
  # short-circuiting once multiple merge paths converge on a shared
  # ancestor. Results are then sorted by commit_time DESC, matching
  # what github.com/.../commits/<branch> shows.
  #
  # branch_memberships is still around as a cache for the dual
  # question ("which branches contain commit X?"), but its `position`
  # column is no longer read — Step 5 drops it.

  # Relation of every commit reachable from this branch's head,
  # ordered newest-first by commit_time. Supports normal Rails
  # chaining and Kaminari .page(n).per(n).
  def ordered_commits
    Commit.from("(#{reachable_commits_sql}) AS commits")
          .order('commits.commit_time DESC')
  end

  # Count of commits reachable from this branch's head.
  def reachable_commit_count
    return 0 unless head_id

    ActiveRecord::Base.connection.select_value(<<~SQL).to_i
      WITH RECURSIVE reachable(id) AS (
        SELECT #{head_id.to_i}::bigint
        UNION
        SELECT cr.parent_id
          FROM commit_relations cr
          JOIN reachable ON cr.child_id = reachable.id
      )
      SELECT COUNT(*) FROM reachable
    SQL
  end

  # Raw SQL for the recursive CTE that finds every commit reachable from
  # this branch's head. Public so callers can wrap it in their own
  # subquery — the commits index, for example, layers cursor-pagination
  # WHERE clauses on top to get the "newer than" lookahead it needs.
  def reachable_commits_sql
    return 'SELECT * FROM commits WHERE 1 = 0' unless head_id

    <<~SQL
      WITH RECURSIVE reachable(id) AS (
        SELECT #{head_id.to_i}::bigint
        UNION
        SELECT cr.parent_id
          FROM commit_relations cr
          JOIN reachable ON cr.child_id = reachable.id
      )
      SELECT commits.*
        FROM commits
        JOIN reachable ON commits.id = reachable.id
    SQL
  end

  ###############################################
  # PHASE 3.5 RECONCILE-WITH-GITHUB ENTRY POINT #
  ###############################################
  #
  # Catch-up path for when local state has drifted from GitHub —
  # missed webhooks, cold-start after deploy, periodic safety net.
  # Synthesizes webhook-shaped events from the diff between
  # local state and `api.branches`, then dispatches each one
  # through BranchSyncJob exactly like a real webhook would.
  # That way the two code paths can't diverge in subtle ways.
  #
  # API cost: 1 `api.branches` call + 1 `api.compare` per branch
  # whose head has moved. On a healthy system most branches are
  # unchanged and skipped.
  def self.reconcile_with_github
    github = api_branches.index_by(&:name)
    local  = Branch.all.index_by(&:name)

    moved, created = 0, 0

    github.each do |name, gh_branch|
      gh_head = gh_branch[:commit][:sha]
      local_branch = local[name]

      if local_branch.nil?
        BranchSyncJob.perform_now(synthetic_event(name, after: gh_head,
                                                        created: true))
        created += 1
      elsif local_branch.head&.sha != gh_head
        before_sha = local_branch.head&.sha || ZERO_SHA
        BranchSyncJob.perform_now(synthetic_event(name, before: before_sha,
                                                        after: gh_head,
                                                        created: before_sha == ZERO_SHA))
        moved += 1
      end
    end

    deleted = 0
    (local.keys - github.keys).each do |orphan_name|
      BranchSyncJob.perform_now(synthetic_event(orphan_name, deleted: true))
      deleted += 1
    end

    { created: created, moved: moved, deleted: deleted,
      unchanged: github.size - created - moved }
  end

  def self.synthetic_event(branch_name, before: ZERO_SHA, after: ZERO_SHA,
                           created: false, deleted: false)
    {
      'ref'     => "refs/heads/#{branch_name}",
      'before'  => before,
      'after'   => after,
      'created' => created,
      'deleted' => deleted,
      'forced'  => false,
      'commits' => []
    }
  end

  #####################################
  # PHASE 3.5 MEMBERSHIP MAINTENANCE  #
  #####################################
  #
  # These are the membership-side entry points BranchSyncJob calls
  # after Commit.ingest_payload_{commits,edges} have populated the
  # commit + topology rows. Two cases:
  #
  #   - `absorb_commits` for the simple linear push: just add
  #     (branch, commit) memberships for each new commit in the push.
  #   - `absorb_merge` for merge commits, which implicitly bring every
  #     commit reachable from the foreign parent(s) onto this branch.
  #     The walk uses a recursive CTE so the round-trip to the DB is one
  #     query regardless of how deep the foreign branch was.

  def absorb_commits(commit_ids)
    return if commit_ids.empty?

    rows = commit_ids.map { |id| { branch_id: self.id, commit_id: id } }
    BranchMembership.insert_all(rows, unique_by: %i[commit_id branch_id])
  end

  # Add memberships for every commit reachable from any of `foreign_parent_ids`
  # via commit_relations, stopping at commits already in this branch (their
  # ancestors are already members too, by induction). Used when a merge
  # commit brings a side branch's history into this branch.
  #
  # The "stop" flag inside the CTE prevents the recursive term from walking
  # past commits already in the branch — important when the side branch
  # is old enough that its merge-base is thousands of commits back.
  def absorb_merge(foreign_parent_ids)
    return if foreign_parent_ids.empty?

    # All integers; cast through to_i defensively even though the IDs
    # come from internal lookups, not user input.
    branch_id = id.to_i
    anchors_values = foreign_parent_ids.map { |i| "(#{i.to_i})" }.join(', ')

    sql = <<~SQL
      WITH RECURSIVE walk(id, stop) AS (
        SELECT v.id::bigint, EXISTS(
          SELECT 1 FROM branch_memberships bm
            WHERE bm.commit_id = v.id AND bm.branch_id = #{branch_id}
        )
        FROM (VALUES #{anchors_values}) AS v(id)
        UNION
        SELECT cr.parent_id, EXISTS(
          SELECT 1 FROM branch_memberships bm
            WHERE bm.commit_id = cr.parent_id AND bm.branch_id = #{branch_id}
        )
        FROM commit_relations cr
        JOIN walk ON cr.child_id = walk.id
        WHERE NOT walk.stop
      )
      SELECT id FROM walk WHERE NOT stop
    SQL

    reachable_ids = ActiveRecord::Base.connection
                                      .select_values(sql)
                                      .map(&:to_i)

    absorb_commits(reachable_ids)
  end

  # use github api to create an array of hashes that contain data about all
  # known branches
  def self.api_branches(**params)
    api.branches(@@repo_path, **params)
  end

  # NOTE: Branch.api_update_branch_names, Branch.api_update_branches,
  # Branch#api_update, Branch#api_reorder_all_commits,
  # Branch#api_reorder_commits, Branch#earliest_duplicated_position,
  # Branch#update_membership, Branch#root, and Branch#recursive_assign_root
  # all lived here before Phase 3.5. They were the per-branch fetch-and-
  # reposition path that Branch.reconcile_with_github + BranchSyncJob +
  # BranchBackfillJob replace, and they all read or wrote
  # branch_memberships.position (now dropped). Deleted in Step 5.

  # convenience methods to get a hold of branches quickly

  # access a branch by name
  def self.named(branch_name)
    find_by(name: branch_name)
  end

  # access main branch (most useful one, and likely a default)
  def self.main
    named('main')
  end

  # special getter to allow including associations
  def get_head(includes: nil)
    return head unless includes

    Commit.includes(includes).find(head_id)
  end

  # Return up to `window` commits on either side of `commit` in this
  # branch, plus `commit` itself, sorted newest-first by commit_time.
  # Up to 2*window + 1 commits total. Uses branch_memberships as the
  # "is this commit in the branch?" cache (still maintained by the
  # sync flow); ordering is by commit_time so it agrees with
  # ordered_commits.
  def nearby_commits(commit, window = 2)
    return [commit] unless branch_memberships.exists?(commit_id: commit.id)

    older = commits.where('commit_time < ?', commit.commit_time)
                   .order(commit_time: :desc)
                   .limit(window)
                   .to_a
    newer = commits.where('commit_time > ?', commit.commit_time)
                   .order(commit_time: :asc)
                   .limit(window)
                   .to_a

    (newer.reverse + [commit] + older)
  end

  # get branches that have been updated in the last +weeks+ weeks
  def self.recent(weeks: 4)
    Branch.where('updated_at > ?', weeks.weeks.ago).order(:name)
  end

  def self.older(weeks: 4)
    Branch.where('updated_at <= ?', weeks.weeks.ago).order(:name)
  end

  # Build the sparkline payload used in the commits list and commit
  # detail hero. Walks the branch's `ordered_commits` newest-first and
  # returns the last N commits packaged with the categorical states the
  # sparkline cells render: build status + tests status (see
  # CommitState#commit_state for the vocabulary).
  #
  # Yes, this is N+1 in commit_state — each commit's helpers touch its
  # submissions and test_case_commits. Profile and batch once the
  # sparkline is wired into actual views. For now 12 commits is well
  # under the threshold worth pre-optimizing.
  def sparkline_data(limit: 12)
    ordered_commits.limit(limit).map do |commit|
      state = commit.commit_state
      {
        commit: commit,
        sha: commit.short_sha,
        build_status: state[:build][:status],
        tests_status: state[:tests][:status]
      }
    end
  end

  # Return test_case_commits for the same test case on commits near
  # `test_case_commit.commit` in this branch's commit_time ordering.
  # Up to 2*window + 1 entries, sorted newest-first by commit_time.
  # Searches up to 50 commits on either side for ones that have a
  # TestCaseCommit for this test case (test cases may not be present
  # on every commit, especially newly-added ones).
  def nearby_test_case_commits(test_case_commit, window = 2)
    commit    = test_case_commit.commit
    test_case = test_case_commit.test_case

    return [test_case_commit] unless branch_memberships
                                       .exists?(commit_id: commit.id)

    older_tccs = nearby_tccs_in_direction(
      test_case, commit.commit_time, direction: :older, limit: window
    )
    newer_tccs = nearby_tccs_in_direction(
      test_case, commit.commit_time, direction: :newer, limit: window
    )

    newer_tccs + [test_case_commit] + older_tccs
  end

  private

  # Walk up to 50 commits in `direction` from `anchor_time`, returning
  # at most `limit` TestCaseCommits for `test_case`. `direction: :older`
  # returns them newest-first (so they come right after the anchor in
  # display order); `:newer` returns them in oldest-first order (so the
  # caller can prepend without re-sorting).
  def nearby_tccs_in_direction(test_case, anchor_time, direction:, limit:)
    op, order_dir = case direction
                    when :older then ['<', :desc]
                    when :newer then ['>', :asc]
                    end

    commit_ids = commits.where("commit_time #{op} ?", anchor_time)
                        .order(commit_time: order_dir)
                        .limit(50)
                        .pluck(:id)
    return [] if commit_ids.empty?

    found = TestCaseCommit.where(commit_id: commit_ids, test_case: test_case)
                          .includes(:commit)
                          .to_a

    # Re-sort by the commit_time order we walked in, then take up to limit
    sorted = found.sort_by { |tcc| tcc.commit.commit_time }
    sorted.reverse! if direction == :older
    sorted.first(limit)
  end

  public

  def to_s
    self.name
  end
end
