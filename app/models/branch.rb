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

  private

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

  public

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

  def self.api_update_branch_names(**params)
    github_branch_names = api_branches(**params).map(&:name)
    existing_branch_names = Branch.all.pluck(:name)

    # batch insert of new branches
    to_add = github_branch_names - existing_branch_names
    branch_hashes_to_insert = to_add.map { |b_name| { name: b_name } }
    unless branch_hashes_to_insert.empty?
      Branch.insert_all(branch_hashes_to_insert)
    end

    # delete orphaned branches
    to_delete = Branch.where(name: existing_branch_names - github_branch_names)

    # using destroy_all would be simpler, but much more time-consuming, as
    # it would need to issue a delete statement for each affected branch
    # membership. Instead, we delete the branch memberships first, and then
    # kill the branches themseleves with delete_all, which is closer to the
    # database, and requires more babysitting (branch memberships are dependent
    # on branches, so they should die when the branch dies)
    unless to_delete.empty?
      to_delete.each do |branch|
        branch.branch_memberships.delete_all
      end
      to_delete.delete_all
    end


    # api_branches(**params).each do |branch_hash|
    #   unless Branch.exists?(name: branch_hash[:name])
    #     Branch.create(name: branch_hash[:name])
    #   end
    # end
  end

  # use github api to instantiate missing branches, update their head commits,
  # and determine if they are merged or not. If +simple+ is used, only
  # instantiates missing branches; does not try to set head nodes or determine
  # merge status (useful for running before updating the tree, before we have
  # the commits themselves)
  def self.api_update_branches(**params)
    branch_data = api_branches(**params)

    ########################################################
    ### STEP 1: UPDATE WHICH BRANCHES ARE PRESENT AT ALL ###
    ########################################################
    github_branch_names = branch_data.map(&:name)
    existing_branch_names = Branch.all.pluck(:name)

    # batch insert of new branches
    # need to include timestamps since insert_all doesn't create them
    # automatically
    to_add = github_branch_names - existing_branch_names
    timestamp = Time.zone.now
    branch_hashes_to_insert = to_add.map do |b_name|
      {
        name: b_name,
        created_at: timestamp,
        updated_at: timestamp
      }
    end
    unless branch_hashes_to_insert.empty?
      # do upsertion, skipping existing branches (shouldn't be any, but just
      # in case!)
      Branch.upsert_all(branch_hashes_to_insert, unique_by: :name)
    end

    #######################################################################
    ### STEP 2: CHECK HEAD COMMITS, TRIGGERING A LARGER UPDATE IF HEAD ###
    ### COMMIT IS DIFFERENT                                            ###
    ######################################################################
    branch_data.each do |branch_hash|
      branch = Branch.find_by(name: branch_hash[:name])
      # bail if the branch isn't found... but this shouldn't happen (see step 1)
      next unless branch

      # If head commit differs from what GitHub reports, do a proper update
      # of the branch (involves one or more api calls)
      new_head_commit = Commit.find_by(sha: branch_hash[:commit][:sha])

      if new_head_commit
        # new head commit already exists in db; only update if it isn't
        # the current head commit
        branch.api_update unless branch.head &&
                                 (branch.head.sha == new_head_commit.sha)
      else
        # new head commit is not already in db (most common case).
        # Update commits on branch and then set the head commit
        branch.api_update
      end
    end

    ########################################
    ### STEP 3: DELETE ORPHANED BRANCHES ###
    ########################################
    # Drop memberships before the branches so the unguarded branch_id FK
    # column doesn't end up pointing at non-existent branches. Orphaned
    # commits are picked up by the db:cleanup_orphaned_commits rake task.
    to_delete = Branch.where(name: existing_branch_names - github_branch_names)
    return if to_delete.empty?

    Branch.transaction do
      BranchMembership.where(branch_id: to_delete.pluck(:id)).delete_all
      to_delete.delete_all
    end
  end

  # brings commits in a branch and their order up to date by syncing order
  # with that provided by GitHub api, adding any missing commits along the
  # way
  def api_update
    ##############################
    ### STEP 1: UPDATE COMMITS ###
    ##############################

    # gather commits from GitHub api
    # for new branch, just grab first 100 commits (bleeds into past branches)
    commits_data = Branch.api(auto_paginate: false).
                          commits(Branch.repo_path, sha: self.name, per_page: 100)
    unless commits.length.zero?
      # for existing branch, grab up to 500 commits in successive api calls
      # limit of 500 is abitrary, but the madness must stop somewhere if we
      # can't find any existing commits
      call_count = 1
      while commits.where(sha: commits_data.pluck(:sha)).count.zero? &&
            call_count < 5
        commits_data.concat(
          Branch.api(auto_paginate: false).commits(
            Branch.repo_path, sha: self.name, per_page: 100,
            page: call_count + 1
          )
        )
        call_count += 1
      end
    end

    # add/update commits to database. Hold on to commits so we can more easily
    # create memberships. Thankfully, these commits should already be ordered
    # (most recent first), so we can use this
    # to generate the new ordering. We also add memberships at this point,
    # (implicit in create_or_update_from_github_hash) but they will be updated
    # by the ordering code below
    commits = commits_data.map do |gh_hash|
      Commit.create_or_update_from_github_hash(github_hash: gh_hash,
                                               branch: self)
    end

    # for new commits, they need their test cases loaded. This is an expensive
    # set of api calls that grows with the number of "new" commits.
    commits.select { |c| c.test_case_count == 0 }.each do |c|
      c.api_update_test_cases
      c.save
    end

    ############################################
    ### STEP 2: UPDATE MEMBERSHIPS/POSITIONS ###
    ############################################

    # get position of "oldest" commit in this collection (if there is one)
    earliest_position = (branch_memberships.where.not(commit: commits).
                                            maximum(:position) || 0) + 1

    # create the membership hashes. Reverse the list of ids so that "old"
    # commits come first, and thus have smaller positions, which are derived
    # from their position in this reversed array
    membership_hashes = []
    commits.reverse.each_with_index do |commit, i|
      membership_hashes << {
        branch_id: self.id,
        commit_id: commit.id,
        position: earliest_position + i
      }
    end

    # dump it all into the database, updating existing membership's positions
    # and creating the rest from scratch. upsert_all is amazing.
    BranchMembership.upsert_all(membership_hashes,
                                unique_by: [:commit_id, :branch_id])

    # update head to most recent (highest position) commit, and save to the db
    self.head = branch_memberships.where.not(position: nil).
                                   order(position: :desc).first.commit
    self.save
  end




  # Gets list of ALL commits from github and uses it to assign orders to
  # all branch memberships. Makes abusive amounts of calls to GitHub API that
  # will scale poorly with repo size. No controller calls this; only for
  # manual maintenance.
  def api_reorder_all_commits
    # get ordered list of ALL shas for commits in this branch
    shas = Commit.api_commits(sha: self.name).map do |commit_hash|
      commit_hash[:sha]
    end.reverse

    # create hash that maps sha to id for creating/updating memberships
    sha_to_id = {}
    commits.select(:id, :sha).each do |commit|
      sha_to_id[commit.sha] = commit.id
    end

    # create/update hashes of attributes for branch memberships
    membership_hashes = []
    shas.each_with_index do |sha, i|
      membership_hashes << {
        branch_id: self.id,
        commit_id: sha_to_id[sha],
        position: i,
      }
    end
    BranchMembership.upsert_all(membership_hashes,
                                unique_by: [:commit_id, :branch_id])
  end

  # UNTESTED
  # find the earliest position with multiple branch memberships and reorder
  # memberships down to a little before that
  def api_reorder_commits
    # find lowest duplicated position and how many commits "deep" we need to
    # go to straighten things out
    min_pos = earliest_duplicated_position
    return unless min_pos
    membership_count = branch_memberships.count
    depth = membership_count - min_pos

    # build up a list of commit data from GitHub api until we have enough to
    # "go deep enough". Limit calls to 50, just in case things go crazy
    shas = []
    page = 1
    num_calls = 0
    while shas.length < depth && num_cals < 50
      shas.concat(
        Branch.api(auto_paginate: false).commits(
          Branch.repo_path,
          sha: self.name,
          page: page,
          per_page: 100
        ).map { |commit| commit[:sha] }
      )
      page += 1
      num_cals += 1
    end

    # reassign memberships with proper ordering, but first destroy memberships
    # of commits that think they are in this range, but didn't come out of
    # api call
    branch_memberships.includes(:commit).where('position >= ?', min_pos).
                                         where.not(commit: {sha: shas})


  end

  # UNTESTED
  # earliest position assigned to at least two branch memberships. Useful
  # when knowing when and where to reorder commits (like post-merge)
  def earliest_duplicated_position
    dups = branch_memberships.select(:position).group(:position).
                              having('count(*) > 1').pluck(:position).
                              reject(:nil?)
    return nil unless dups.length > 0

    dups.min

  end

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

  # # ordered commits (most recent first; according to GitHub API ordering)
  # # within some window around a particular commit, assumed to be in the branch
  # def nearby_commits(commit, window = 2)
  #   # number of days to look on either side of the commit's commit time
  #   time_window = 10

  #   # minimum number of commits to make sure we get from the api call
  #   min_commits = [10, commits.count].min
  #   loc = nil

  #   is_head = (commit == head)

  #   num_found = 0
  #   # commit may not be in the right window. Commit time is time commited, but
  #   # not necessarily when it hit the branch (especially for stale pull
  #   # requests). There's probably a better way, but for now, just keep
  #   # expanding the window around the commit time until the commit shows up in
  #   # the list. Don't make more than 3 api calls, though, as this can quickly
  #   # abuse the rate limit.
  #   api_count = 0
  #   until (loc && num_found >= min_commits) || api_count > 3
  #     latest = [DateTime.now, time_window.days.after(commit.commit_time)].min
  #     earliest = (2 * time_window).days.before(latest)
  #     commit_shas = Commit.api.commits_between(
  #       Commit.repo_path,
  #       earliest,
  #       latest,
  #       name
  #     ).map { |c| c[:sha] }
  #     loc = commit_shas.index(commit.sha)

  #     # set loc to nil if it is zero, but commit is not head. This is because
  #     # we should not have this commit appearing as the latest  when it is not
  #     # actully the head commit
  #     loc = nil if (loc == 0 && !is_head)

  #     num_found = commit_shas.length
  #     api_count += 1
  #     time_window *= 2
  #   end
  #   start_i = [0, loc - window].max
  #   stop_i = [commit_shas.length - 1, loc + window].min
  #   commit_shas = commit_shas[(start_i..stop_i)]

  #   commits.where(sha: commit_shas).to_a.sort! do |a, b|
  #     commit_shas.index(a.sha) <=> commit_shas.index(b.sha)
  #   end
  # end

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



  # # ordered commits (most recent first; according to GitHub API ordering)
  # # within some window around a particular commit, assumed to be in the branch
  # def nearby_test_case_commits(test_case_commit, window = 2)
  #   test_case = test_case_commit.test_case
  #   commit = test_case_commit.commit
  #   is_head = (commit == head)

  #   # number of days to look on either side of the commit's commit time
  #   time_window = 10

  #   # minimum number of commits to make sure we get from the api call
  #   min_tccs = [10, commits.count].min
  #   loc = nil

  #   all_commits = nil

  #   num_found = 0
  #   # commit may not be in the right window. Commit time is time commited, but
  #   # not necessarily when it hit the branch (especially for stale pull
  #   # requests). There's probably a better way, but for now, just keep
  #   # expanding the window around the commit time until the commit shows up in
  #   # the list. Don't make more than 3 api calls, though, as this can quickly
  #   # abuse the rate limit.
  #   api_count = 0
  #   until (loc && num_found >= min_tccs) || api_count > 3
  #     latest = [DateTime.now, time_window.days.after(commit.commit_time)].min
  #     earliest = (2 * time_window).days.before(latest)
  #     commit_shas = Commit.api.commits_between(
  #       Commit.repo_path,
  #       earliest,
  #       latest,
  #       name
  #     ).map { |c| c[:sha] }
  #     loc = commit_shas.index(commit.sha)

  #     # set loc to nil if it is zero, but commit is not head. This is because
  #     # we should not have this commit appearing as the latest  when it is not
  #     # actully the head commit
  #     loc = nil if (loc == 0 && !is_head)

  #     if loc
  #       num_found = commit_shas.length
  #       # if we found enough commits, check to see if we have enough that
  #       # actually contain the test case we want
  #       if loc && num_found > min_tccs
  #         all_commits = commits.where(sha: commit_shas)
  #         num_found = test_case_commits.where(
  #           commit: all_commits,
  #           test_case: test_case
  #         ).count
  #       end
  #     end

  #     time_window *= 2
  #     api_count += 1
  #   end

  #   # fetch all test case commits. Wasteful, but we don't know which ones
  #   # we need until we know which commits actually have this test case. Also
  #   # arrange them. We'll throw out any outside of the desired window
  #   # afterwards
  #   tccs = test_case_commits.includes(:commit, :test_case).where(
  #     commit: all_commits, test_case: test_case
  #   ).to_a.sort! do |a, b|
  #     commit_shas.index(a.commit.sha) <=> commit_shas.index(b.commit.sha)
  #   end

  #   loc = tccs.index(test_case_commit)
  #   start_i = [0, loc - window].max
  #   stop_i = [tccs.length - 1, loc + window].min
  #   tccs[(start_i..stop_i)]
  # end

  # update branch membership for all commits in branches
  def update_membership
    # first make sure that all the proper commits in this branch are stored
    # in this branch.
    # recursive_assign_root

    # Now make sure that all commits are parts of each of the branches that the
    # head commit belongs to. Go through each branch besides this one present
    # on the head node of this branch, and ensure that any missing memberships
    # are created.
    other_branches = head.branches.to_a - [self]
    branch_commit_ids = commits.pluck(:id)

    other_branches.each do |other_branch|
      already_in = other_branch.commits.pluck(:id)

      # find commit ids that are in this branch, but are missing in the
      # other branch that it was merged into. Create all needed memberships
      not_in = branch_commit_ids - already_in
      memberships_to_insert = not_in.map do |commit_id|
        {
          commit_id: commit_id,
          branch_id: other_branch.id,
          created_at: Time.zone.now,
          updated_at: Time.zone.now
        }
      end

      # do upsertion, treating any memberships with matching commit/branches
      # as already existing
      unless memberships_to_insert.empty?
        BranchMembership.upsert_all(memberships_to_insert,
                                    unique_by: [:commit_id, :branch_id])
      end
    end
  end

  def root
    res = commits.find_by(parents_count: 0)
    # make sure we actually found the root commit
    unless res == Commit.root
      recursive_assign_root(root: res)
      res = commits.find_by(parents_count: 0)
    end
    res
  end

  # make sure the root of a branch is the true root of the entire repo
  # this is bad for the database since it could require repeated
  def recursive_assign_root(current_root: nil)
    current_root ||= commits.find_by(parents_count: 0) || head
    return if current_root == Commit.root

    current_root.parents.each do |parent|
      next if commits.include? parent

      BranchMembership.create(branch_id: id, commit_id: parent.id)
      recursive_assign_root(current_root: parent)
    end
  end

  def to_s
    self.name
  end

end
