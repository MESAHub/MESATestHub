class Branch < ApplicationRecord
  belongs_to :head, class_name: 'Commit', optional: true

  has_many :branch_memberships, dependent: :destroy
  has_many :commits, through: :branch_memberships
  has_many :test_case_commits, through: :commits

  scope :merged, -> { where(merged: true) }
  scope :unmerged, -> { where(merged: false) }

  # use github api to create an array of hashes that contain data about all
  # known branches
  def self.api_branches(**params)
    puts '#######################'
    puts 'API retrieving branches'
    puts '#######################'
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

    # STEP 1: UPDATE WHICH BRANCHES ARE PRESENT AT ALL
    ##################################################
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

    # STEP 2: UPDATE HEAD COMMITS, TRIGGERING A LARGER UPDATE IF HEAD COMMIT
    # IS MISSING
    ########################################################################
    branch_data.each do |branch_hash|
      branch = Branch.find_by(name: branch_hash[:name])
      # bail if the branch isn't found... but this shouldn't happen (see step 1)
      next unless branch

      # update head commit. If that commit doesn't exist, update that branch's
      # commits ONLY
      new_head_commit = Commit.find_by(sha: branch_hash[:commit][:sha])
      if new_head_commit
        branch.head = new_head_commit
      else
        Commit.api_update_tree(branch: branch)
        new_head_commit = Commit.find_by(sha: branch_hash[:commit][:sha])
        branch.head = new_head_commit if new_head_commit
      end

      branch.save
    end

    # STEP 3: MAKE SURE COMMITS ON MERGED BRANCHES NOW BELONG TO THEIR NEW
    # BRANCHES, THEN DELETE ALL ORPHANED BRANCHES AND THEIR MEMBERSHIPS
    # (THOUGH NOT THEIR COMMITS)
    #########################################################################
  
    # make sure that all commits in a merged branch belong to at least the
    # branches that its head node belongs to
    # Branch.merged.each { |branch| branch.update_membership }

    # delete orphaned branches, but first make sure their commits have homes
    to_delete = Branch.where(name: existing_branch_names - github_branch_names)

    # this ensures that all commits in a soon-to-be-deleted branch are members
    # of the same branch their head commit is in. Probably redundant since we
    # should already have updated the branch into which they are merged
    to_delete.each(&:update_membership)

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

    nil
  end


  # Gets list of ALL commits from github and uses it to assign orders to
  # all branch memberships. Makes abusive amounts of calls to GitHub API that
  # will scale poorly with repo size.
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

    # create hashses of attributes for branch memberships
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

  # ordered commits (most recent first; according to GitHub API ordering)
  # within some window around a particular commit, assumed to be in the branch
  def nearby_commits(commit, window = 2)
    # number of days to look on either side of the commit's commit time
    time_window = 10

    # minimum number of commits to make sure we get from the api call
    min_commits = [10, commits.count].min
    loc = nil

    is_head = (commit == head)

    num_found = 0
    # commit may not be in the right window. Commit time is time commited, but
    # not necessarily when it hit the branch (especially for stale pull
    # requests). There's probably a better way, but for now, just keep 
    # expanding the window around the commit time until the commit shows up in
    # the list. Don't make more than 3 api calls, though, as this can quickly
    # abuse the rate limit.
    api_count = 0
    until (loc && num_found >= min_commits) || api_count > 3
      latest = [DateTime.now, time_window.days.after(commit.commit_time)].min
      earliest = (2 * time_window).days.before(latest)
      commit_shas = Commit.api.commits_between(
        Commit.repo_path,
        earliest,
        latest,
        name
      ).map { |c| c[:sha] }
      loc = commit_shas.index(commit.sha)

      # set loc to nil if it is zero, but commit is not head. This is because
      # we should not have this commit appearing as the latest  when it is not
      # actully the head commit
      loc = nil if (loc == 0 && !is_head)

      num_found = commit_shas.length
      api_count += 1
      time_window *= 2
    end
    start_i = [0, loc - window].max
    stop_i = [commit_shas.length - 1, loc + window].min
    commit_shas = commit_shas[(start_i..stop_i)]

    commits.where(sha: commit_shas).to_a.sort! do |a, b|
      commit_shas.index(a.sha) <=> commit_shas.index(b.sha)
    end
  end

  # ordered commits (most recent first; according to GitHub API ordering)
  # within some window around a particular commit, assumed to be in the branch
  def nearby_test_case_commits(test_case_commit, window = 2)
    test_case = test_case_commit.test_case
    commit = test_case_commit.commit
    is_head = (commit == head)

    # number of days to look on either side of the commit's commit time
    time_window = 10

    # minimum number of commits to make sure we get from the api call
    min_tccs = [10, commits.count].min
    loc = nil

    all_commits = nil

    num_found = 0
    # commit may not be in the right window. Commit time is time commited, but
    # not necessarily when it hit the branch (especially for stale pull
    # requests). There's probably a better way, but for now, just keep 
    # expanding the window around the commit time until the commit shows up in
    # the list. Don't make more than 3 api calls, though, as this can quickly
    # abuse the rate limit.
    api_count = 0
    until (loc && num_found >= min_tccs) || api_count > 3
      latest = [DateTime.now, time_window.days.after(commit.commit_time)].min
      earliest = (2 * time_window).days.before(latest)
      commit_shas = Commit.api.commits_between(
        Commit.repo_path,
        earliest,
        latest,
        name
      ).map { |c| c[:sha] }
      loc = commit_shas.index(commit.sha)

      # set loc to nil if it is zero, but commit is not head. This is because
      # we should not have this commit appearing as the latest  when it is not
      # actully the head commit
      loc = nil if (loc == 0 && !is_head)

      if loc
        num_found = commit_shas.length
        # if we found enough commits, check to see if we have enough that
        # actually contain the test case we want
        if loc && num_found > min_tccs
          all_commits = commits.where(sha: commit_shas)
          num_found = test_case_commits.where(
            commit: all_commits,
            test_case: test_case
          ).count
        end
      end

      time_window *= 2
      api_count += 1
    end

    # fetch all test case commits. Wasteful, but we don't know which ones
    # we need until we know which commits actually have this test case. Also
    # arrange them. We'll throw out any outside of the desired window
    # afterwards
    tccs = test_case_commits.includes(:commit, :test_case).where(
      commit: all_commits, test_case: test_case
    ).to_a.sort! do |a, b|
      commit_shas.index(a.commit.sha) <=> commit_shas.index(b.commit.sha)
    end

    loc = tccs.index(test_case_commit)
    start_i = [0, loc - window].max
    stop_i = [tccs.length - 1, loc + window].min
    tccs[(start_i..stop_i)]
  end

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
