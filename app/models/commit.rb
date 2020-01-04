class Commit < ApplicationRecord
  has_many :test_case_commits
  has_many :submissions
  has_many :test_case_instances

  has_many :test_cases, through: :test_case_commits
  has_many :computers, through: :submissions

  validates_uniqueness_of :sha
  validates_presence_of :author, :author_email, :message, :commit_time

  def self.repo
    # handle into Git repo
    
    # short circuit assignment to avoid re-instantiation
    @repo ||= Rugged::Repository.new(Rails.root.join('public', 'mesa-git'))
    @repo
  end

  def self.branch_names
    # array of names (strings) of branches in repo
    names = repo.branches.map { |branch| branch.name }

    # force 'master' to be first if it exists
    if names.include?('master')
      names.insert(0, names.delete('master'))
    end
    names
  end

  def self.head_commit_shas
    # hash mapping branch names to head commits SHA of respective branch
    repo.branches.map { |branch| branch.target.oid }
  end

  def self.create_from_rugged(commit)
    # take a rugged commit object and create a database entry
    attributes = {
      sha: commit.oid,
      author: commit.author[:name],
      author_email: commit.author[:email],
      commit_time: commit.author[:time],
      message: commit.message
    }
    create(attributes)
  end

  def self.update_commits(head_commit)
    # starting from a rugged commit object, create necessary commits in 
    # database to replicate complete history
    repo.walk(head_commit).each do |commit|
      break if exists?(sha: commit.oid)
      create_from_rugged(commit)
    end
  end 

  def self.update_branches
    # iterate through branches and ensure all paths through graph are already
    # present in the databse, creating any that are necessary
    repo.branches.each do |branch|
      update_commits(branch.target)
    end
  end

  def self.all_in_branch(branch_name)
    # ActiveRecord query for all commits in a branch

    # first get list of SHAs for all such commits, then find them in the
    # database. To do this, walk through repo starting at the head node of the
    # branch desired
    # 
    # Bail if given a bad branch name
    return nil unless branch_names.include?(branch_name)
    # Take first (only) branch with matching name
    shas = repo.walk(repo.branches.select do |branch|
      branch.name == branch_name
    end.first.target).map { |commit| commit.oid }
    where(sha: shas, order: :commit_time)
  end

  def <=>(commit_1, commit_2)
    # sort commits according to their datetimes, with recent commits FIRST
    commit_2.commit_datetime <=> commit_1.commit_datetime
  end
end
