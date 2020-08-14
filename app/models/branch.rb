class Branch < ApplicationRecord
  belongs_to :head, class_name: 'Commit', optional: true

  has_many :branch_memberships, dependent: :destroy
  has_many :commits, through: :branch_memberships

  scope :merged, -> { where(merged: true) }
  scope :unmerged, -> { where(merged: false) }

  # use github api to create an array of hashes that contain data about all
  # known branches
  def self.api_branches(**params)
    api.branches(@@repo_path, **params)
  end

  def self.api_update_branch_names(**params)
    api_branches(**params).each do |branch_hash|
      unless Branch.exists?(name: branch_hash[:name])
        Branch.create(name: branch_hash[:name])
      end
    end
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
      # branch is merged if its head commit has children. Otherwise, it is the
      # latest commit (a true head commit)
      branch.merged = (head_commit.children.count > 0)
      branch.save
    end

    # make sure each branch extends back to the root commit
    Branch.all.each { |branch| branch.recursive_assign_root }

    # make sure that all commits in a merged branch belong to at least the
    # branches that its head node belongs to
    Branch.merged.each do |branch|
      branch.update_membership
    end
    nil
  end

  # convenience methods to get a hold of branches quickly

  # access a branch by name
  def self.named(branch_name)
    find_by(name: branch_name)
  end

  # access master branch (most useful one, and likely a default)
  def self.master
    named('master')
  end



  # update branch membership for all commits in branches
  def update_membership
    # first make sure that all the proper commits in this branch are stored
    # in this branch.
    recursive_assign_root

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
      BranchMembership.create(
        not_in.map do |commit_id|
          {commit_id: commit_id, branch_id: other_branch.id}
        end)
    end
  end

  def root
    res = commits.find_by(parents_count: 0)
    # make sure we actually found the root commit
    unless res == Commit.root
      recursive_assign_root 
      res = commits.find_by(parents_count: 0)
    end
    res
  end

  # make sure the root of a branch is the true root of the entire repo
  # this is bad for the database since it could require repeated 
  def recursive_assign_root(root: nil)
    root ||= self.root
    return if root == Commit.root
    self.root.parents.each do |parent|
      next if commits.include? parent
      BranchMembership.create(branch_id: id, commit_id: parent.id)
      recursive_assign_root(root: parent)
    end
  end

  def to_s
    self.name
  end

end
