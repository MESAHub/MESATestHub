class Commit < ApplicationRecord
  has_many :test_case_commits
  has_many :submissions
  has_many :test_case_instances

  has_many :test_cases, through: :test_case_commits
  has_many :computers, through: :submissions

  validates_uniqueness_of :sha
  validates_presence_of :author, :author_email, :message, :commit_time

  paginates_per 25

  # PROBLEM: Need to keep track of commits being a merge commit (multiple
  # parents). Right now we don't do this at all. We can always go back to last
  # merge, but then master will stop at previous merge (same for other
  # branches, but problem is most obvious with master).
  # 
  # Perhaps the best option is to do the suggested combination of sort orders
  # indicated by rugged's github page:
  #   walker.sorting(Rugged::SORT_TOPO | Rugged::SORT_DATE)
  # From the source code for Rugged on SORT_TOPO:
  # * Sort the repository contents in topological order (parents before
  # * children); this sorting mode can be combined with time sorting to
  # * produce git's "time-order".
  # 
  # and for SORT_DATE
  # * Sort the repository contents by commit time;
  # * this sorting mode can be combined with
  # * topological sorting.
  # 
  # NO ONE WILL TELL ME WHAT THIS MEANS! As far as I can tell , this only
  # _really_ matters when we go through a branch back in time, which may be
  # uncommon. On a single branch with no merge points, there is no distinction.
  # 
  # [Non-]Conclusion: there's no unambiguous linear ordering of commits, and 
  # we'll just have to deal with random discontinuities. For now, I'm relying
  # on the default ordering of Rugged
  
  # I hope this is sorting topologically (parents before children), and then by
  # date when there's a tie (merge commits), and finally reversing. That might
  # not make sense
  DEFAULT_SORTING = Rugged::SORT_TOPO | Rugged::SORT_DATE | Rugged::SORT_REVERSE

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
    repo.walk(head_commit, DEFAULT_SORTING).each do |commit|
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
    end.first.target, DEFAULT_SORTING).map { |commit| commit.oid }
    where(sha: shas, order: :commit_time)
  end

  def self.commits_before(anchor, depth, inclusive: true)
    # retrieve all commits before a certain commit in a branch to some depth
    # 
    # +anchor+ specifies the commit to measure back from (the latest commit),
    # +depth+ is number of commits to go back
    # +inclusive+ is a boolean that determines whether or not to include the
    # anchor commit in the returned list of commits, it does NOT affect the
    # last commit (i.e., setting +depth+ to 100 could produce 100 commits if 
    # +inclusive+ is false, or 101 if it is true)
    
    # Take first (only) branch with matching name
    counter = 0
    shas = []
    repo.walk(anchor, DEFAULT_SORTING).each do |commit|
      # stop the walk if we've gotten to the desired epth, otherwise
      # add new SHA, increment counter, and keep walking
      break if counter > depth
      shas << commit.oid
      counter += 1
    end
    # get rid of first SHA if we don't want to include the anchor commit
    shas = shas[(1..-1)] unless inclusive
    where(sha: shas, order: :commit_time)
  end

  def self.commits_after(anchor, height, inclusive: true)
    # retrieve all commits after a certain commit in a branch to some height
    # 
    # +anchor+ specifies the commit to measure forward from (the earliest commit),
    # +height+ is number of commits to go forward
    # +inclusive+ is a boolean that determines whether or not to include the
    # anchor commit in the returned list of commits, it does NOT affect the
    # last commit (i.e., setting +depth+ to 100 could produce 100 commits if 
    # +inclusive+ is false, or 101 if it is true)
    # 
    # *NOTE* This is harder to do than commits_before because commits only know
    # about their parents rather than their children.
    
    # Take first (only) branch with matching name
    shas = []
    repo.walk(anchor, DEFAULT_SORTING).each do |commit|
      # append commits until we get to desired commit
      shas << commit.oid
      break if commit.oid == anchor.sha
    end
    # optionally trim off anchor commit as well as excess commits if they exist
    if inclusive
      # trim excess elements of the beginning if we had to go more than
      # +height+ down the rabbit hole
      shas = shas[(shas.length - (height + 1))..-1] if shas.length > height + 1
    else
      # exclude anchor (last point)
      shas = shas[0...-1]
      # trim to proper length (height) by lopping elements off the beginning
      shas = shas[(shas.length - height)..-1] if shas.length > height
    end
    where(sha: shas, order: :commit_time)
  end  

  def <=>(commit_1, commit_2)
    # sort commits according to their datetimes, with recent commits FIRST
    commit_2.commit_datetime <=> commit_1.commit_datetime
  end
end
