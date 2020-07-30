class Branch < ApplicationRecord
  belongs_to :head, class_name: 'Commit', optional: true

  has_many :branch_memberships, dependent: :destroy
  has_many :commits, through: :branch_memberships

  # use github api to create an array of hashes that contain data about all
  # known branches
  def self.api_branches(**params)
    api.branches(@@repo_path, **params)
  end

  # use github api to instantiate missing branches, update their head commits,
  # and determine if they are merged or not. If +simple+ is used, only
  # instantiates missing branches; does not try to set head nodes or determine
  # merge status (useful for running before updating the tree, before we have
  # the commits themselves)
  def self.api_update_branches(simple: false, **params)
    api_branches(**params).each do |branch_hash|
      branch = if Branch.exists?(name: branch_hash[:name])
                 Branch.find_by(name: branch_hash[:name])
               else
                 Branch.new(name: branch_hash[:name])
               end
      unless simple
        head_commit = if Commit.exists?(sha: branch_hash[:commit][:sha])
                        Commit.find_by(sha: branch_hash[:commit][:sha])
                      else
                        Commit.api_create(sha: branch_hash[:commit][:sha])
                      end
        branch.head = head_commit
        if head_commit.children.count > 0
          branch.merged = true
        else
          branch.merged = false
        end
        branch.save
      end
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

  # access all merged branches
  def self.merged
    Branch.where(merged: true)
  end

  # access all unmerged branches
  def self.unmerged
    Branch.where(merged: false)
  end

end
