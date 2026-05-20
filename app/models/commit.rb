class Commit < ApplicationRecord
  
  # Git structure
  has_many :branch_memberships, dependent: :destroy
  has_many :branches, through: :branch_memberships

  # Parent/child edges from the git DAG. Stored as rows in commit_relations
  # so that merge commits (which have multiple parents) and octopus merges
  # are representable without losing any edges, and so that ancestor /
  # descendant walks can stay in the database.
  has_many :parent_relations, class_name: 'CommitRelation',
                              foreign_key: :child_id,
                              dependent: :destroy
  has_many :parents, through: :parent_relations, source: :parent

  has_many :child_relations,  class_name: 'CommitRelation',
                              foreign_key: :parent_id,
                              dependent: :destroy
  has_many :children, through: :child_relations, source: :child

  # from parsing do1_test_source in tested modules
  has_many :test_case_commits, dependent: :destroy

  # submitted data
  has_many :submissions, dependent: :destroy
  has_many :computers, through: :submissions
  has_many :test_cases, through: :test_case_commits
  has_many :test_instances, through: :test_case_commits

  validates_uniqueness_of :sha, :short_sha
  validates_presence_of :sha, :short_sha, :author, :author_email, :message,
    :commit_time

  after_create :api_update_test_cases
  before_save :update_scalars

  paginates_per 50


  #################################
  # GITHUB COMPARE-PAYLOAD INGEST #
  #################################
  #
  # Entry points for the Phase 3.5 sync flow. The webhook handler kicks
  # off a BranchSyncJob, which calls `api.compare(before, after)` once
  # to get the canonical ordered list of commits in the push (with
  # parent SHAs — the webhook payload itself doesn't include those).
  # These helpers then upsert the commit rows and the
  # parent->child edges in two bulk operations.

  # Path pattern for the test-source files we'd need to re-read from
  # GitHub if they changed in a commit. Any modified/added path matching
  # this is a signal that the commit's test case list might differ from
  # its parent's.
  TEST_SOURCE_PATTERN = %r{(?:\A|/)test_suite/do1_test_source\z}.freeze

  # Bulk-insert commits from a GitHub API response (commits or compare
  # endpoint, both use the same nested shape). Returns a hash mapping
  # sha => id for every commit ingested OR already present.
  #
  # Uses insert_all (DO NOTHING on conflict), not upsert_all: real
  # GitHub commits are immutable, and overwriting them via upsert risks
  # clobbering test-case scalars (test_case_count, passed_count, status,
  # etc.) that were maintained by the original update_scalars callback
  # for commits ingested before Phase 3.5.
  #
  # status is explicitly set to -1 ("untested") so newly-inserted
  # commits don't show as passing — the schema default of 0 means
  # "passing", which is wrong for a commit that has no test data yet.
  # populate_test_cases_for then sets it correctly.
  #
  # Bypasses ActiveRecord validations and the `after_create
  # :api_update_test_cases` callback. Test-case ingestion is a separate
  # step (populate_payload_test_cases) that the caller must run AFTER
  # ingest_payload_edges has wired up the parent edges — otherwise the
  # copy-from-parent optimization can't find the parent.
  def self.ingest_payload_commits(commit_hashes)
    return {} if commit_hashes.empty?

    timestamp = Time.zone.now
    rows = commit_hashes.map do |gh|
      hash_from_github(gh).merge(
        created_at: timestamp,
        updated_at: timestamp,
        status: -1
      )
    end

    Commit.insert_all(rows, unique_by: :sha)

    Commit.where(sha: commit_hashes.map { |gh| gh[:sha] })
          .pluck(:sha, :id)
          .to_h
  end

  # Populate TestCaseCommit rows for any commit in `commit_hashes` that
  # currently has none (test_case_count == 0). MUST be called after
  # ingest_payload_edges so the copy-from-parent step can resolve
  # commit.parents.first.
  #
  # Optional `file_changes_by_sha:` is a `sha => Array<String>` map of
  # added/modified file paths per commit (from the webhook payload's
  # commits[] array). When a commit's paths don't touch any
  # `*/test_suite/do1_test_source` file, we can copy from parent for
  # free; when they do touch, we re-fetch via api.content. When the
  # map isn't provided (backfill / reconcile path), populate falls back
  # to copy-from-parent as the optimistic default — correct for MESA's
  # workflow where source files rarely change.
  #
  # Iteration order matters: commits must be processed in commit_time
  # ASC order so a commit's parent is populated before the commit
  # itself. Otherwise a chain of newly-ingested commits with no TCCs
  # cascades — each commit's copy-from-parent fails (parent not
  # populated yet) and falls back to an api.content call. Under
  # backfill that's 300 API calls + per-commit DB writes per page of
  # 100, vs. ~3 API calls + 99 fast copies with the right order. We
  # load into memory rather than use find_each so the order isn't
  # overridden by find_each's primary-key batching.
  def self.populate_payload_test_cases(commit_hashes, sha_to_id,
                                       file_changes_by_sha: nil)
    ids = commit_hashes.map { |gh| sha_to_id[gh[:sha]] }.compact
    return if ids.empty?

    Commit.where(id: ids, test_case_count: 0)
          .order(commit_time: :asc)
          .each do |commit|
      sources_touched = file_changes_by_sha&.dig(commit.sha)&.then do |paths|
        paths.any? { |p| p.match?(TEST_SOURCE_PATTERN) }
      end
      populate_test_cases_for(commit, sources_touched: sources_touched)
    end
  end

  # Populate TestCaseCommit rows for a freshly-ingested commit. Three
  # paths in order of preference:
  #
  # 1. If we know sources are unchanged (sources_touched: false), copy
  #    the parent's TCCs. Zero API calls.
  # 2. If we don't know whether sources changed (sources_touched: nil)
  #    but the parent has TCCs, copy them as the best-effort default.
  #    Zero API calls. Correct for MESA's workflow where source files
  #    rarely change; if they did change, the next test submission for
  #    this commit will surface the discrepancy and the operator can
  #    re-fetch via `rake test_cases:populate`.
  # 3. Otherwise (sources_touched: true, or parent has no TCCs, or
  #    parent isn't in DB): fall back to api_update_test_cases, which
  #    reads do1_test_source for each module via the GitHub API.
  #    Three API calls per commit.
  #
  # Returns :copied, :fetched, or :no_parent_no_fetch (the last means
  # there's truly nothing to populate and the caller should know).
  def self.populate_test_cases_for(commit, sources_touched: nil)
    if sources_touched != true && copy_test_cases_from_parent(commit)
      :copied
    else
      commit.api_update_test_cases
      :fetched
    end
  end

  # Returns true if TCCs were successfully copied from the parent commit;
  # false if there's no parent or the parent has no TCCs to copy.
  #
  # Filters out test_case_ids the commit already has TCCs for, so this
  # is idempotent in the partial-population case (some TCCs already
  # present, others missing). There's no unique index on
  # (commit_id, test_case_id) in the schema, so the filter is how we
  # avoid duplicates rather than ON CONFLICT.
  def self.copy_test_cases_from_parent(commit)
    parent = commit.parents.first
    return false unless parent

    parent_tc_ids = parent.test_case_commits.pluck(:test_case_id)
    return false if parent_tc_ids.empty?

    existing_tc_ids = commit.test_case_commits.pluck(:test_case_id)
    to_create = parent_tc_ids - existing_tc_ids

    if to_create.any?
      timestamp = Time.zone.now
      rows = to_create.map do |tc_id|
        {
          commit_id: commit.id,
          test_case_id: tc_id,
          status: -1,
          submission_count: 0,
          computer_count: 0,
          checksum_count: 0,
          passed_count: 0,
          failed_count: 0,
          created_at: timestamp,
          updated_at: timestamp
        }
      end
      TestCaseCommit.insert_all(rows)
    end

    commit.save  # before_save :update_scalars refreshes commit-level scalars
    true
  end

  # Insert parent->child edges into commit_relations for every commit
  # in `commit_hashes` whose parents are resolvable in the local DB.
  # `sha_to_id` is the mapping returned by ingest_payload_commits;
  # parents that aren't in it (e.g., the parent of the oldest commit
  # in the compare set, which sits on the branch's previous head) are
  # looked up in the DB in one extra query.
  #
  # Orphan parents (parent SHA we've never seen) are skipped, same as
  # backfill. The unique index on (child_id, parent_id) makes reruns
  # no-ops.
  #
  # Returns the count of newly-inserted edges.
  def self.ingest_payload_edges(commit_hashes, sha_to_id)
    return 0 if commit_hashes.empty?

    unknown_parent_shas = commit_hashes.flat_map { |gh|
      gh[:parents].map { |p| p[:sha] }
    }.uniq - sha_to_id.keys

    if unknown_parent_shas.any?
      sha_to_id = sha_to_id.merge(
        Commit.where(sha: unknown_parent_shas).pluck(:sha, :id).to_h
      )
    end

    edges = []
    commit_hashes.each do |gh|
      child_id = sha_to_id[gh[:sha]]
      next unless child_id

      gh[:parents].each_with_index do |parent, idx|
        parent_id = sha_to_id[parent[:sha]]
        next unless parent_id

        edges << { parent_id: parent_id,
                   child_id: child_id,
                   parent_index: idx }
      end
    end

    return 0 if edges.empty?

    CommitRelation.insert_all(edges,
                              unique_by: %i[child_id parent_id]).length
  end

  ####################
  # GITHUB API STUFF #
  ####################
  #
  # NOTE: general stuff in application_record.rb

  # gets all commits from GitHub API and creates or updates them in the
  # database. Does NOT assign branches or test case commits. Those must be
  # done AFTER this
  
  def self.api_commits(auto_paginate: true, **params)
    begin
      data = api(auto_paginate: auto_paginate).commits(repo_path, **params)
    rescue Octokit::NotFound
      return nil
    else
      data
    end
  end

  def self.api_create(sha: nil, **params)
    create_or_update_from_github_hash(
      github_hash: api.commit(repo_path, sha, **params)
    )
  end

  # from a hash, probably generated by an api call, create or update a commit.
  # NOTE: this does NOT set parents/children. This is because they are not
  # guaranteed to exist, and this could lead to cyclical api calls as parents
  # of parents of parents are retrieved and created. Instead, you should
  # set up ALL commits first, and then establish relations with one giant
  # call that hits the api only once
  def self.create_or_update_from_github_hash(github_hash: nil, branch: nil)
    commit = if Commit.exists?(sha: github_hash[:sha])
               find_by(sha: github_hash[:sha])
             else
               new(sha: github_hash[:sha])
             end
    commit.update(hash_from_github(github_hash))

    # now establish branch membership
    if branch.is_a? Branch
      unless BranchMembership.exists?(branch: branch, commit: commit)
        BranchMembership.create(branch: branch, commit: commit)
      end
    end

    commit
  end

  # NOTE: Commit.api_update_tree and Commit.api_update_memberships
  # lived here before Phase 3.5. They were the bulk re-sync paths that
  # the new Branch.reconcile_with_github + BranchSyncJob +
  # BranchBackfillJob + Commit.populate_payload_test_cases stack
  # replaces. Deleted in Step 5 along with the position column.

  def self.hash_from_github(github_hash)
    # convert hash from a github api_request representing a commit to 
    # a hash ready to be inserted into the database
    # +github_hash+ a hash for one commit resulting from a github webhook
    # push payload
    {
      sha: github_hash[:sha],
      short_sha: github_hash[:sha][(0...7)],
      author: github_hash[:commit][:author][:name],
      author_email: github_hash[:commit][:author][:email],
      commit_time: github_hash[:commit][:author][:date],
      message: github_hash[:commit][:message],
      github_url: github_hash[:html_url]
    }
  end

  #####################################
  # GENERAL USE AND SEARCHING/SORTING #
  #####################################

  def self.parse_sha(sha, branch: 'main', includes: nil)
    branch = Branch.named(branch) || Branch.main
    if (sha.downcase == 'head') || (sha.downcase == 'auto')
      puts "Getting head commit of #{branch.name}"
      return branch.get_head unless includes

      branch.get_head(includes: includes)
    # otherwise ignore branch and just fine the actual commit
    elsif sha.length == 7
      return Commit.find_by(short_sha: sha) unless includes

      Commit.includes(includes).find_by(short_sha: sha)
    else
      return Commit.find_by(sha: sha) unless includes

      Commit.includes(includes).find_by(sha: sha)
    end
  end

  # get the [Rails] head commit of a particular branch
  # Params:
  # +branch+:: branch for which we want the head node
  def self.head(branch: Branch.main, includes: nil)
    branch.head unless includes
    Commit.includes(includes).find(branch.head_id)
  end

  # determine an optimal commit for testing on a particular computer
  # Params
  # +computer+:: computer that is seeking a commit to test
  # +allow_optional+:: optional boolean designating whether or not to allow
  #   commits that request all optional inlists are run; default is +true+
  # +allow_fpe+:: optional boolean designating whether or not to allow commits
  #   that request fpe checks be on; default is +true+
  # +allow_skip+:: optional boolean designating whether or not to allow commits
  #   that indicate they should be skipped; default is +false+
  # +max_age+:: optional integer that specifies the absolute oldest commits
  #   to check. Default is 10
  # +branch+:: optional branch to which commits should be restricted. Default
  #   is +nil+, indicating that all should be checked, but with a preference
  #   for recent commits in +main+
  def self.test_candidate(computer:, allow_optional: true, allow_fpe: true,
    allow_converge: true, allow_skip: false, max_age: 10, branch: nil)
    # search iteratively for commits that match the criteria AND do not have
    # submissions from this computer already. Start with commits from the
    # last day, and then search first in main, but then in all branches.
    # If none are found, double the time window. Do this until we find a
    # commit or we get to the max age with zero commits.
    if branch
      candidates = branch.commits.where(created_at:max_age.days.ago..Time.now)
                                 .order(created_at: :desc)
                                 .to_a

      # rule out candidates that ask for optional tests (if we disallow them),
      # ask for fpe checks (if we disallow them), or ask to be skipped 
      # (unless we allow them). If the commit is still valid, check for
      # existing submissions on the commit for the computer
      candidates.each do |commit|
        res = true
        res &= !commit.ci_optional? unless allow_optional
        res &= !commit.ci_fpe? unless allow_fpe
        res &= !commit.ci_converge? unless allow_converge
        res &= !commit.ci_skip? unless allow_skip
        next unless res
        # make sure commit still lives in a branch
        next if commit.branches.count.zero?
        if Submission.where(commit: commit, computer: computer).count.zero?
          return commit
        end
      end
      return nil
    else
      # first check main, since it should have highest priority. Skip if
      # there's no main branch yet (without this guard, recursing with
      # branch: nil would re-enter the else branch and spin forever).
      if Branch.main
        main_candidate = self.test_candidate(computer: computer,
          allow_optional: allow_optional, allow_fpe: allow_fpe,
          allow_skip: allow_skip, max_age: max_age, branch: Branch.main)
        return main_candidate if main_candidate
      end

      # no matching candidates in main? Check elsewhere. Same as
      # search on specific branch, but we search on all commits (definite
      # code ducplication happening here)
      candidates = Commit.where(created_at:max_age.days.ago..Time.now)
                         .order(created_at: :desc)
                         .to_a

      # rule out candidates that ask for optional tests (if we disallow them),
      # ask for fpe checks (if we disallow them), or ask to be skipped 
      # (unless we allow them). If the commit is still valid, check for
      # existing submissions on the commit for the computer
      candidates.each do |commit|
        res = true
        res &= !commit.ci_optional? unless allow_optional
        res &= !commit.ci_fpe? unless allow_fpe
        res &= !commit.ci_converge? unless allow_converge
        res &= !commit.ci_skip? unless allow_skip
        next unless res
        # make sure commit still lives in a branch
        next if commit.branches.count.zero?
        if Submission.where(commit: commit, computer: computer).count.zero?
          return commit
        end
      end
      return nil
    end
  end
  ####################
  # INSTANCE METHODS #
  ####################

  # use GitHub api to pull `do1_test_source` for each module and set up
  # test case commits if they don't exist
  def api_test_cases
    cases_present = {}
    TestCase.modules.each do |mod|
      source_file = "/#{mod}/test_suite/do1_test_source"
      begin
        contents = Base64.decode64(
          Commit.api.content(
            Commit.repo_path, path: source_file, query: {ref: sha}).content)
        cases_present[mod] = []
        contents.split("\n").each do |line|
          if /^\s*do_one\s+(\S+)/ =~ line
            cases_present[mod] << $1
          elsif /^\s*return\s*$/ =~ line
            break
          end
        end
      rescue Octokit::NotFound
        puts "No do1_test_source found for module #{mod} in commit #{self}. "\
             "Skipping it."
      end
    end
    cases_present
  end

  def api_update_test_cases
    TestCaseCommit.create_from_commit(self)
    update_scalars
  end

  # get list of commits that are near in +commit_time+ to this commit. If
  # possible, get +limit+ commits, with equal numbers before and after this
  # commit
  def nearby_commits(branch: Branch.main, limit: 11)
    earliest = branch.commits.order(commit_time: :asc).first.commit_time
    before = branch.commits.where(commit_time: earliest...commit_time).
                            order(commit_time: :desc).limit(limit).reverse.to_a
    after = branch.commits.where(commit_time: commit_time..Time.now
    ).where.not(id: id).order(commit_time: :asc).limit(limit).to_a

    # create list of all commits, including this commit
    all_commits = [before, self, after].flatten.sort do |a, b|
      [a.commit_time, a.message] <=> [b.commit_time, b.message]
    end

    # make sure head commit is at the right location
    if all_commits.include? branch.head
      all_commits << all_commits.delete(Commit.head(branch: branch))
    end

    # if its smaller than the limit, we're done
    return all_commits if all_commits.length <= limit

    # find where +self+ is so we can build an array of the right length
    self_index = all_commits.index(self)
    size = all_commits.length
    res = [self]

    i = 0
    while res.length < limit
      one_before = self_index - i - 1
      one_after = self_index + i + 1
      i += 1

      # try to add elements to the front and back of the array, one by one,
      # stopping if we hit an edge
      res.prepend(all_commits[one_before]) if one_before >= 0
      res.append(all_commits[one_after]) if one_after < size
    end
    res.reject(&:nil?)
  end

  def computer_info
    # One row per unique combination of (computer_id, platform_version,
    # sdk_version, math_backend, compiler, compiler_version). The view at
    # commits/show.html.haml iterates these and reads :computer (+ .user),
    # :spec, :numerator, :denominator, :frac, :compilation — keep all of
    # those keys populated.
    all_subs = submissions.includes(computer: :user).to_a
    return [] if all_subs.empty?

    grouped = all_subs.group_by do |sub|
      [sub.computer_id, sub.platform_version, sub.sdk_version,
       sub.math_backend, sub.compiler, sub.compiler_version]
    end

    # Per-(computer, spec) distinct test_case_id counts in one query.
    ti_counts = test_instances
                .group(:computer_id, :computer_specification)
                .distinct
                .count(:test_case_id)

    # Compilation status is rolled up per computer (not per spec): if any
    # of this computer's submissions disagree on `compiled`, every spec
    # entry for that computer reports :mixed.
    compile_stati_by_computer = all_subs.group_by(&:computer_id)
                                        .transform_values do |subs|
      subs.map(&:compiled).uniq.reject(&:nil?)
    end

    denominator = test_cases.count

    grouped.map do |_key, subs|
      sub = subs.first
      computer = sub.computer
      spec = sub.computer_specification
      numerator = ti_counts[[sub.computer_id, spec]] || 0
      stati = compile_stati_by_computer[sub.computer_id] || []

      compilation = case stati.count
                    when 0 then :unknown
                    when 1 then stati[0] ? :success : :failure
                    else :mixed
                    end

      {
        computer: computer,
        spec: spec,
        numerator: numerator,
        denominator: denominator,
        frac: denominator.zero? ? 0.0 : numerator.to_f / denominator.to_f,
        compilation: compilation
      }
    end
  end

  # note: future optimization would be to make these three "questions" be
  # scalars that are updated at save time. They are all summoned every time we
  # load an index view, meaning we have a 3n+1 situation
  #
  # Each predicate has an early "no test cases yet" guard: without it, the
  # `pluck(...).uniq.count == test_cases.count` form returns `0 == 0` → true
  # for any commit ingested before its test cases land (e.g., commits
  # ingested by the new webhook flow before Step 6 wires up test-case
  # copying). That made every recent commit on the index page light up
  # with all three icons.

  # determine if each test case has been run with all optional inlists
  def run_optional?
    return false if test_cases.empty?
    test_instances.
      where(run_optional: true).
      pluck(:test_case_id).uniq.count == test_cases.count
  end

  # determine if each test case has been run with FPE checks enabled
  def fpe_checks?
    return false if test_cases.empty?
    test_instances.
      where(fpe_checks: true).
      pluck(:test_case_id).uniq.count == test_cases.count
  end

  def fine_resolution?
    return false if test_cases.empty?
    test_instances.
      where(resolution_factor: 0..0.99).
      pluck(:test_case_id).uniq.count == test_cases.count
  end

  # these simply report if the right flag appears in the commit message
  # ideally, these should be added to the database so they can be modified
  # after the fact (and so we can change the convetion). But for now, this
  # will suffice
  def ci_skip?
    # ensure that anything including optional or fpe tests is not thought
    # of as being skipped; usually only appears in merge commit messages
    !!(message =~ /\[\s*ci\s+skip\s*\]/ && !(ci_optional? || ci_fpe?))
  end

  def ci_optional?
    !!(message =~ /\[\s*ci\s+optional(\s+\d+)?\s*\]/)
  end

  # extract the number from a run-optional commit, if there is one
  def ci_optional_n
    return unless ci_optional?
    matchgroup = /\[\s*ci\s+optional(\s+\d+)?\s*\]/.match(message)
    if matchgroup[1]
      return matchgroup[1].strip.to_i
    end
    return nil
  end

  def ci_fpe?
    !!(message =~ /\[\s*ci\s+fpe\s*\]/)
  end

  def ci_converge?
    !!(message =~ /\[\s*ci\s+converge\s*\]/)
  end


  # make this stuff searchable directly on the database without having
  # to summon all the test case commits. This should be called whenever
  # a submission is made and whenever a change is made to a test case commit
  def update_scalars
    self.test_case_count = test_case_commits.count
    self.passed_count = test_case_commits.where(status: [0, 2]).count
    self.failed_count = test_case_commits.where(status: 1).count
    self.mixed_count = test_case_commits.where(status: 3).count
    self.checksum_count = test_case_commits.where.not(
      checksum_count: [0, 1]).count
    self.untested_count = test_case_commits.where(status: -1).count
    self.computer_count = computer_info.count
    self.complete_computer_count = computer_info.select do |spec|
      spec[:frac] == 1.0
    end.count
    self.status = if mixed_count > 0
                    3
                  elsif failed_count > 0
                    1
                  elsif checksum_count > 0
                    2
                  elsif passed_count == test_case_count && test_case_count > 0
                    0
                  else
                    -1
                  end
  end

  # commits/show calls compilation_status, compile_success_count, and
  # compile_fail_count back-to-back; cache the single query they all share
  # so the page does one SELECT instead of three.
  def compile_stati
    @compile_stati ||= submissions.pluck(:compiled)
  end

  #
  # Guide: nil = untested (or unreported)
  #          -1 = no compilation status provided
  #          0  = compiles on all systems so far
  #          1  = fails compilation on all systems so far
  #          2  = mixed results
  # this method just keeps this scheme logically consistent when a new report
  # rolls in, but it DOES NOT save the result to the database.
  def compilation_status
    stati = compile_stati.reject(&:nil?)
    return -1 if stati.empty?
    return 2  if stati.uniq.count > 1
    stati.first ? 0 : 1
  end

  def compile_success_count
    compile_stati.count(true)
  end

  def compile_fail_count
    compile_stati.count(false)
  end

  # branches that this commit is NOT in, in two categories:
  # - branches that have been recently updated
  # - branches that have not been recently updated
  # each collection is sorted by name
  def not_in_branches(weeks: 4)
    # query for all branches that this commit is not in
    bs = Branch.includes(:head).where.not(id: branches.pluck(:id))
    # sort into two categories
    recently_updated = []
    not_recently_updated = []
    bs.each do |b|
      if b.head.commit_time > weeks.weeks.ago
        recently_updated << b
      else
        not_recently_updated << b
      end
    end
    # sort each category by name
    recently_updated.sort_by!(&:name)
    not_recently_updated.sort_by!(&:name)
    {recent: recently_updated, older: not_recently_updated}
  end

  # sort commits according to their datetimes, with recent commits FIRST
  def <=>(commit_1, commit_2)
    commit_2.commit_time <=> commit_1.commit_time
  end

  # default string represenation will be the first 7 characters of the SHA
  def to_s
    short_sha
  end

  # first 80 characters of the first line of the message
  # if first line exceeds 80 characters, chop off last word and add an ellipsis
  # remainder will be accessible via +message_rest+
  def message_first_line(max_len = 70)
    first_line = message.split("\n").first
    return first_line if first_line.length < max_len

    res = ''
    first_line.split(/\s+/).each do |word|
      return "#{res}..." if "#{res} #{word}...".length > max_len

      res = "#{res} #{word}"
    end
  end

  # the latter part of the message not captured by +message_first+
  def message_rest(max_len = 70)
    # if its a short message in one line, we shouldn't have anything left over
    return nil if message_first_line(max_len) == message

    # determine where rest starts by looking at length of first line, but
    # dropping any ellipsis
    first_line = message_first_line(max_len)
    start = message_first_line(max_len).chomp('...').length
    res = message[(start..-1)].strip
    return nil if res.empty?
    
    res = if /.*\.\.\.$/ =~ first_line
            '...' + res.strip
          else
            res.strip
          end
    res.gsub!(/\n(\s*\n)+/, '<br><br>')
    newline_plus_space_matcher = /\n(?<indent>\s+)/
    m = newline_plus_space_matcher.match(res)
    while m
      indent = m[:indent].chars.map do |char|
        case char
        when "\t" then '&#9;'
        when ' ' then '&nbsp;'
        else
          ''
        end
      end.join
      res.sub!(newline_plus_space_matcher, "<br>#{indent}")
      m = newline_plus_space_matcher.match(res)
    end
    res.html_safe
  end
end

class GitError < Exception; end
