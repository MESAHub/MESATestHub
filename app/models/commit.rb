class Commit < ApplicationRecord
  has_many :test_case_commits, dependent: :destroy
  has_many :submissions, dependent: :destroy
  
  has_many :test_cases, through: :test_case_commits
  has_many :test_instances, through: :test_case_commits
  has_many :computers, through: :submissions

  validates_uniqueness_of :sha, :short_sha
  validates_presence_of :sha, :short_sha, :author, :author_email, :message,
    :commit_time

  paginates_per 25

  ###########################################
  # WORKING WITH THE NAVIGATING RUGGED TREE #
  ###########################################

  # I hope this is sorting topologically (parents before children), and then by
  # date when there's a tie (merge commits). That might not make sense
  DEFAULT_SORTING = Rugged::SORT_TOPO | Rugged::SORT_DATE

  def self.repo
    # handle into Git repo
    
    # short circuit assignment to avoid re-instantiation
    @repo ||= Rugged::Repository.new(Rails.root.join('public', 'mesa-git'))
    @repo
  end

  def self.fetch
    # update git repo; should be fired every time a push webhook event comes
    # in to the server
    
    credentials = Rugged::Credentials::UserPassword.new(username: 'wmwolf',
      password: ENV['GIT_TOKEN'])
    # strike out my credentials before this goes live!
    repo.fetch('origin', credentials: credentials)
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

  def self.rugged_get_branch(branch_name)
    # first branch that matches the name. Problematic for repeated names, but
    # we'll cross that bridge when we get there
    return nil unless branch_names.include? branch_name
    repo.branches.select { |branch| branch.name == branch_name }.first
  end

  def self.rugged_get_head(branch_name)
    # head commit of a given branch name
    branch = rugged_get_branch(branch_name)
    return nil if branch.nil?
    branch.target
  end

  ########################################
  # TRANSLATING BETWEEN RAILS AND RUGGED #
  ########################################

  def self.hash_from_rugged(commit)
    # convert a rugged commit instance into a has that is ready to be
    # inserted into the database
    # +commit+ a Rugged::Commit instance

    {
      sha: commit.oid,
      short_sha: commit.oid[(0..7)],
      author: commit.author[:name],
      author_email: commit.author[:email],
      commit_time: commit.author[:time],
      message: commit.message
    }
  end

  def self.create_from_rugged(commit)
    # take a rugged commit object and create a database entry
    # +commit+ a Rugged::Commit instance

    create(hash_from_rugged(commit))
  end

  def self.find_from_rugged(commit)
    # given a rugged commit instance, retrieve the database entry
    # +commit+ a Rugged::Commit instance

    find_by_sha(commit.oid)
  end

  def self.sorted_query(shas, includes: nil)
    # given a list of sorted shas, find the corresponding commits and return
    # them as a sorted list (in the same order as the shas)
    # 
    # +shas+ list of strings corresponding to commit SHAs
    # +includes+ list of arguments that should go to ActiveRecord query
    query = if includes
              where(sha: shas).includes(*includes)
            else
              where(sha: shas)
            end
    query.sort { |c1, c2| shas.index(c1) <=> shas.index(c2) }
  end

  ################################################
  # TRANSLATING BETWEEN RAILS AND GITHUB WEBHOOK #
  ################################################

  def self.hash_from_github(github_hash)
    # convert hash from a github webhook payload representing a commit to 
    # a hash ready to be inserted into the database
    # +github_hash+ a hash for one commit resulting from a github webhook
    # push payload

    {
      sha: github_hash[:id],
      short_sha: github_hash[:id][(0..7)],
      author: github_hash[:author][:name],
      author_email: github_hash[:author][:email],
      commit_time: github_hash[:timestamp],
      message: github_hash[:message],
      github_url: github_hash[:url]
    }
  end

  def self.create_many_from_github_push(payload)
    # take payload from githubs push webhook, extract commits to
    # hashes, and then insert them into the database.
    commits = create(payload[:commits].map { |commit| hash_from_github(commit) })
    TestCaseCommit.create_from_commits(commits)
  end

  #####################################
  # GENERAL USE AND SEARCHING/SORTING #
  #####################################
  
  def self.parse_sha(sha)
    if sha.downcase == 'head'
      Commit.head
    elsif sha.length == 7
      Commit.find_by(short_sha: sha)
    else
      Commit.find_by(sha: sha)
    end
  end


  def self.head(branch_name: 'master', includes: nil)
    # get the [Rails] head commit of a particular branch
    # +branch_name+ branch for which we want the head node
    # +includes+ argument to be passed on to AcitveRecord#includes (pre-load
    # associations)
    rugged_head = rugged_get_head(branch_name)
    return nil unless rugged_head
    if includes
      Commit.where(sha: rugged_head.oid).includes(*includes).first
    else
      Commit.where(sha: rugged_head.oid).first
    end
  end

  def self.all_in_branch(branch_name: 'master', includes: nil)
    # ActiveRecord query for all commits in a branch

    # first get list of SHAs for all such commits, then find them in the
    # database. To do this, walk through repo starting at the head node of the
    # branch desired
    # 
    # +branch_name+ string matching a branch's name. If it isn't found, returns
    # nil
    # +includes+ argument to be passed on to AcitveRecord#includes (pre-load
    # associations)

    # Bail if given a bad branch name (and thus no head commit)
    head = rugged_get_head(branch_name)
    return if head.nil?
    # walk the tree to
    # completion, scraping shas in topological order
    shas = repo.walk(head, DEFAULT_SORTING).map { |commit| commit.oid }
    sorted_query(shas, includes: includes)
  end

  def self.subset_of_branch(branch_name: 'master', size: 25, page: 1,
    includes: nil)
    # Retrieve properly sorted collection of commits, but limit the size
    # 
    # Meant to simulate pagination, but since we have to do sorting on the
    # tree, we can't rely on Rails magic. Instead, we get SHAs of the 
    # relevant commits, find them in the database, and then sort the results
    # accordingly.
    # 
    # +branch_name+ string matching a branch's name. If it isn't found, returns
    # nil
    # +size+ integer describing the "chunk size" of commits to be returned.
    # Defaults to 25
    # +page+ which chunk to get Essentially we'll start at item (page-1) * size
    # and then scrape the next "size" amount of commits
    # +includes+ argument to be passed on to AcitveRecord#includes (pre-load
    # associations)
    head = rugged_get_head(branch_name)
    return if head.nil?

    # define parameters for "pagination"
    counter = 0
    start_recording = (page - 1) * size
    stop_recording = page * size
    shas = []
    repo.walk(head, DEFAULT_SORTING).each do |commit|
      # only start recording when we are deep enough, and stop when we are too
      # deep
      shas.append(commit.oid) if counter >= start_recording
      counter += 1
      break if counter >= stop_recording
    end
    sorted_query(shas, includes: includes)
  end

  def self.commits_before(anchor, depth, inclusive: true, includes: nil)
    # retrieve all commits before a certain commit in a branch to some depth
    # 
    # +anchor+ specifies the commit to measure back from (the latest commit),
    # +depth+ is number of commits to go back
    # +inclusive+ is a boolean that determines whether or not to include the
    # anchor commit in the returned list of commits, it does NOT affect the
    # last commit (i.e., setting +depth+ to 100 could produce 100 commits if 
    # +inclusive+ is false, or 101 if it is true)
    # +includes+ argument to be passed on to AcitveRecord#includes (pre-load
    # associations)
    
    counter = 0
    shas = []
    repo.walk(anchor, DEFAULT_SORTING).each do |commit|
      # stop the walk if we've gotten to the desired depth, otherwise
      # add new SHA, increment counter, and keep walking
      break if counter > depth
      shas << commit.oid
      counter += 1
    end
    # get rid of first SHA if we don't want to include the anchor commit
    shas = shas[(1..-1)] unless inclusive
    sorted_query(shas, includes: includes)
  end

  def self.commits_after(anchor, branch_name, height, inclusive: true,
    includes: nil)
    # retrieve all commits after a certain commit in a branch to some height
    # 
    # +anchor+ specifies the [Rails] commit to measure forward from (the earliest commit),
    # +branch_name+ valid name of a branch on which to search
    # +height+ is number of commits to go forward
    # +inclusive+ is a boolean that determines whether or not to include the
    # anchor commit in the returned list of commits, it does NOT affect the
    # last commit (i.e., setting +depth+ to 100 could produce 100 commits if 
    # +inclusive+ is false, or 101 if it is true)
    # +includes+ argument to be passed on to AcitveRecord#includes (pre-load
    # associations)
    # 
    # *NOTE* This is harder to do than commits_before because commits only know
    # about their parents rather than their children. We start at the head
    # node of the branch and walk back to the anchor, keeping up to +height+
    # commits
    
    # need head to start down the correct branch. We'll find everything
    # down to `anchor` and then only report the last ones we found
    head = rugged_get_head(branch_name)
    return nil if head.nil?

    # Take first (only) branch with matching name
    shas = []
    repo.walk(anchor, DEFAULT_SORTING).each do |commit|
      # append commits until we get to desired commit
      shas << commit.oid
      break if commit.oid == anchor.sha
    end

    # trim off later commits, if needed
    shas = shas[-(height+1)..-1] if shas.length > height + 1
    
    # optionally trim off anchor commit as well as excess commits if they exist
    shas.pop unless inclusive

    # now have proper shas. Go get 'em!
    sorted_query(shas, includes: includes)
  end

  # array of test case names being tested in a particular module
  def test_case_names(mod)
    test_suite_dir = File.join(mod, 'test_suite')
    Commit.repo.checkout(sha, options={paths: 
      [File.join(test_suite_dir, 'do1_test_source'),
       File.join(test_suite_dir, 'list_tests')]
    })
    current_dir = Dir.pwd
    full_test_suite_dir = File.join(Commit.repo.path, '..', test_suite_dir)
    return [] unless Dir.exist? full_test_suite_dir
    Dir.chdir(full_test_suite_dir)
    res = `./list_tests`.split("\n").map do |line|
      /^\d+\s+(.+)$/.match(line)[1]
    end
    Dir.chdir(current_dir)
    res
  end

  def <=>(commit_1, commit_2)
    # sort commits according to their datetimes, with recent commits FIRST
    commit_2.commit_datetime <=> commit_1.commit_datetime
  end

  def to_s
    # default string represenation will be the first 7 characters of the SHA
    short_sha
  end

  def message_first_line
    # first 80 characters of the first line of the message
    message.split("\n").first[0,80]
  end
end
