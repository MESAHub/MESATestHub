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
    # puts '#######################'
    # puts 'API retrieving branches'
    # puts '#######################'
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
    branch_data.each do |branch_hash|
      branch = if Branch.exists?(name: branch_hash[:name])
                 Branch.find_by(name: branch_hash[:name])
               else
                 Branch.new(name: branch_hash[:name])
               end
      head_commit = if Commit.exists?(sha: branch_hash[:commit][:sha])
                      Commit.find_by(sha: branch_hash[:commit][:sha])
                    else
                      Commit.api_create(sha: branch_hash[:commit][:sha])
                    end
      branch.head = head_commit
      branch.save
    end

    # make sure each branch extends back to the root commit
    # Branch.all.each { |branch| branch.recursive_assign_root }

    # make sure that all commits in a merged branch belong to at least the
    # branches that its head node belongs to
    Branch.merged.each { |branch| branch.update_membership }
    nil
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
      num_found = commit_shas.length
      time_window *= 2
      api_count += 1
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
        { commit_id: commit_id, branch_id: other_branch.id }
      end

      unless memberships_to_insert.empty?
        BranchMembership.upsert(memberships_to_insert)
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
