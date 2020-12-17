class TestCaseCommit < ApplicationRecord
  belongs_to :commit
  belongs_to :test_case
  has_many :test_instances
  has_many :instance_inlists, through: :test_instances
  has_many :inlist_data, through: :instance_inlists
  has_many :submissions, through: :test_instances
  has_many :computers, through: :test_instances

  validates_presence_of :status, :submission_count, :commit_id, :test_case_id,
    :checksum_count

  @@status_decoder = {
    -1 => :untested,
    0 => :passing,
    1 => :failing,
    2 => :mixed_checksums,
    3 => :mixed
  }

  paginates_per 50

  @@status_encoder = @@status_decoder.invert

  # synthesize all test case commits necessary (and implicitly test cases
  # necessary) from a list of commits; attempts to determine the test cases
  # being tested in a particular commit
  def self.create_from_commits(commits)
    commits.each do |commit|
      TestCaseCommit.create_from_commit(commit)
    end
  end

  def self.create_from_commit(commit)
    # go through each module and create necessary test cases and test case
    # commits
    commit.api_test_cases.each do |mod, test_case_names|
      # create any missing (new) test cases
      existing_cases = TestCase.where(name: test_case_names, module: mod).to_a
      existing_names = existing_cases.pluck(:name)
      to_create = test_case_names - existing_names
      to_create.each { |tc_name| puts tc_name }
      TestCase.transaction do
        to_create.each do |new_name|
          existing_cases << TestCase.create(name: new_name, module: mod)
        end
      end
      # now create any missing test case commits
      existing_tccs = TestCaseCommit.where(test_case: existing_cases,
                                           commit: commit)
      missing_tcc_cases = existing_cases - existing_tccs.includes(:test_case).map(&:test_case)
      # do all test case commit creations in one transaction (hopefully this
      # is better on the database? Not really sure...)
      TestCaseCommit.transaction do
        missing_tcc_cases.each do |test_case|
          test_case.test_case_commits.create(commit: commit)
        end
      end
    end
  end

  def update_and_save_scalars
    # update all scalars, which are counts of interesting quantities and the
    # integer status, indicating passing/failing/mixed/multiple checksums/
    # untested. Finally, saves the model. These help in doing rapid queries
    # rather than having to load oodles of records when querying many 
    # test_case_commits
    update_submission_count
    update_computer_count
    update_checksum_count
    update_status
    update_last_tested
    save
  end

  def update_submission_count
    # updates, but does not save, the number of submissions to this test
    # case for this commit
    self.submission_count = submissions.count
  end

  def update_computer_count
    # updates, but does not save, the number of unique computers that have
    # made submissions to this test case for this commit. Only call after
    # +update_submission_count+
    self.computer_count = submission_count.zero? ? 0 : computers.uniq.count
  end

  def unique_checksums
    # all non-empty, non-nill checksums from submissions to this test case for
    # this commit. Also ignore instances that ran optional inlists, since
    # they are not necessarily expected to have identical checksums
    self.test_instances.where.not(run_optional: true).pluck(:checksum).uniq
      .reject(&:nil?).reject(&:empty?)
  end

  def update_checksum_count
    # updates, but does not save, the number of unique checksums that computers
    # have submitted for this test case for this commit
    self.checksum_count = unique_checksums.count
  end

  def update_last_tested
    # updates, but does not save, the datetime of the most recent submission
    # to this test case for this commit
    self.last_tested = test_instances.pluck(:created_at).max
  end

  def update_status
    # determine if this test case in this commit is in a passing, failing,
    # mixed, multiple checksum, or untested state. DO THIS AFTER ALL OTHER
    # UPDATE_* METHODS TO ENSURE ACCURACY
    
    # assume untested unless there is at least one submission
    self.status ||= @@status_encoder[:untested]
    return unless submission_count.positive?

    outcomes = test_instances.pluck(:passed).uniq
    if outcomes.count == 1
      # all results are the same, either passing or failing
      self.status = if outcomes.first
                      # if only outcome was true, all are passing
                      @@status_encoder[:passing]
                    else
                      # only outcomes was false; all are failing
                      @@status_encoder[:failing]
                    end
    elsif outcomes.count > 1
      # multiple outcomes (true and false present), so it's mixed
      self.status = @@status_encoder[:mixed]
    end
    # if all are passing, insure that checksums match
    if self.status == @@status_encoder[:passing] && self.checksum_count > 1
      self.status = @@status_encoder[:mixed_checksums]
    end
  end

  def passing
    test_instances.where(passed: true)
  end

  def failing
    test_instances.where(passed: false)
  end

  # TODO: update all methods below to work with a specified branch, and thus
  # query for the proper depth of commits in that branch

  def relevant_instances_to_depth(depth: 100, branch: Branch.main, force: false)
    # search query for all instances of this test case that have been tested
    # by the same computers as this test case commit back +depth+ commit
    # 
    # By default, return a memoized commit if it exists, but force a new 
    # search if +force+ is true
    # 
    # *NOTE* This is sloppy. We are assuming that the +depth+ keyword is not
    # often changed, and it is behaving more like an instance variable since it
    # is shared among several methods. Probably good enough for now, though.
    return @relevant_instances if @relevant_instances && !force
    # commits = Commit.subset_of_branch(branch: branch, depth: depth)
    commits = branch.commits.order(commit_time: :desc).limit(depth)
    query = test_case.test_instances.where(computer: computers,
      commit: commits, passed: true).includes(:computer)
    @relevant_instances = query.to_a
    return @relevant_instances
  end

  def recent_runtime_statistics_by_computer(runtime_type: :rn, depth: 100)
    # Generate hash linking computers to runtime statistics for this test
    # 
    # Searches back to <tt>depth</tt> revisions ago and compiles average
    # runtime of type <tt>runtime_type</tt>, which must be one of
    # - +:rn+
    # - +:re+
    # - +:total+
    # and then returns a hash with keys that are computers and values that
    # are themselves hashes with keys of <tt>:avg</tt> and <tt>:std</tt>, which
    # yield the average and standard deviations of the runtimes for those
    # computers
    runtime_query = TestInstance.runtime_query(runtime_type)
    return nil if runtime_query.nil?
    res = {}
    computers.uniq.each do |computer|
      # instances run by this computer in the last N versions
      all_with_runtime = relevant_instances_to_depth(depth: depth).select do |instance|
        instance.computer == computer && !instance[runtime_query].nil?
        # test_case.test_instances.where(computer: computer,
        # mesa_version: (version.number-depth)...version.number).where.not(
        # runtime_query => nil)
      end
      next unless all_with_runtime.count > 5
      runtimes = all_with_runtime.pluck(runtime_query)

      res[computer] = {}
      avg = runtimes.inject(:+) / runtimes.count.to_f
      res[computer][:avg] = avg

      # calculate sample standard deviation, since we don't use all values
      res[computer][:std] = (runtimes.inject(0) do |res, elt|
        res + (elt.to_f - avg.to_f)**2
      end / (runtimes.count - 1)) ** (0.5)
    end
    res
  end

  def slow_instances(depth: 100, threshold: 4, min_delta_t: 5)
    # Generates hash linking runtime type to lists of slow instances
    # 
    # "Slow" instances are defined to be instances having runtimes that, on a
    # computer-by-computer basis, are more than +threshold+ standard deviations
    # longer than the average, with both statistics computed over the last
    # +depth+ revisions (total revisions, not revisions tested).
    # 
    # *NOTE* to make this fast, load test case versions by including
    # test instances _and_ computers, via something like
    # 
    #    TestCaseCommit.where(version: oldest..newest).includes(:computers, :test_instances)
    #    
    # Otherwise you'll make many abusive calls to the database in this method.
    res = {}
    statistics = {}
    statistics[:rn] = recent_runtime_statistics_by_computer(runtime_type: :rn,
      depth: depth)
    statistics[:re] = recent_runtime_statistics_by_computer(runtime_type: :re,
      depth: depth)
    statistics[:total] = recent_runtime_statistics_by_computer(
      runtime_type: :total, depth: depth)
    runtime_queries = {}
    [:rn, :re, :total].each do |run_type|
      runtime_queries[run_type] = TestInstance.runtime_query(run_type)
    end
    [:rn, :re, :total].each do |run_type|
      runtime_query = runtime_queries[run_type]
      computers.each do |computer|
        # determining if it is "slow" by comparing to # of standard devs. from
        # the average runtime
        #
        # find slowest passing in current test case version (may be multiple!) by
        # by identifying all passing from the same computer, then sorting on the
        # appropriate runtime in ascending order, then take the last
        slowest = test_instances.select do |ti|
          ti.computer == computer && ti.passed
        end.sort_by { |ti| ti[runtime_query] }.last

        # skip if we can't find the proper runtime
        next unless slowest && slowest[runtime_query]

        # skip if we have no statistics
        next if statistics[run_type][computer].nil? || statistics[run_type][computer].empty?

        # record the slowest as well as the average and standard deviation
        # used to select it
        avg = statistics[run_type][computer][:avg]
        std = statistics[run_type][computer][:std]
        if slowest[runtime_query] > avg + [threshold * std, min_delta_t].max
          to_add = {instance: slowest, time: slowest[runtime_query], avg: avg,
            std: std}
          if res[run_type]
            res[run_type][computer] = to_add
          else
            res[run_type] = {computer => to_add}
          end
        end
      end
    end
    res
  end

  def recent_memory_statistics_by_computer(runtime_type: :rn, depth: 100)
    # Generate hash linking computers to memory statistics for this test
    # 
    # Searches back to +depth+ revisions ago and compiles average
    # runtime of type +runtime_type+, which must be one of
    # - +:rn+
    # - +:re+
    # - +:total+
    # and then returns a hash with keys that are computers and values that
    # are themselves hashes with keys of +:avg+ and +:std+, which
    # yield the average and standard deviations of the runtimes for those
    # computers
    memory_query = TestInstance.memory_query(runtime_type)
    return nil if memory_query.nil?
    res = {}
    computers.uniq.each do |computer|
      # instances run by this computer in the last +depth+ versions
      all_with_usage = relevant_instances_to_depth(depth: depth).select do |instance|
        instance.computer == computer && !instance[memory_query].nil?
      end

      # set lower limit to make sure we have "statistics"
      next unless all_with_usage.count > 5
      
      usages = all_with_usage.pluck(memory_query)
      # NOTE: this is here because a divide by zero error occurred before that
      # the first escape clause SHOULD HAVE CAUGHT. I don't understand this, so
      # we might be missing some data in our searches if something is going
      # wrong.
      next unless usages.count > 5
      res[computer] = {}
      avg = usages.inject(:+) / usages.count.to_f
      res[computer][:avg] = avg

      # calculate sample standard deviation, since we don't use all values
      res[computer][:std] = (usages.inject(0) do |res, elt|
        res + (elt.to_f - avg.to_f)**2
      end / (usages.count - 1)) ** 0.5
    end
    res
  end

  def inefficient_instances(depth: 100, threshold: 4, min_delta_GB: 0.1)
    # Generates hash linking runtime type to lists of memory-hogging instances
    # 
    # "Inefficient" instances are defined to be instances having memory usages
    # that, on a computer-by-computer basis, are more than +threshold+ standard
    # deviations larger than the average, with both statistics computed over
    # the last +depth+ revisions (total revisions, not revisions tested).
    # 
    # *NOTE* to make this fast, load test case commits by including
    # test instances _and_ computers, via something like
    # 
    #    TestCaseCommit.where(commit: oldest..newest).includes(:computers, :test_instances)
    #    
    # Otherwise you'll make many abusive calls to the database in this method.
    res = {}
    statistics = {}
    statistics[:rn] = recent_memory_statistics_by_computer(runtime_type: :rn,
      depth: depth)
    statistics[:re] = recent_memory_statistics_by_computer(runtime_type: :re,
      depth: depth)
    statistics[:total] = recent_memory_statistics_by_computer(
      runtime_type: :total, depth: depth)
    memory_queries = {}
    [:rn, :re, :total].each do |run_type|
      memory_queries[run_type] = TestInstance.memory_query(run_type)
    end
    [:rn, :re, :total].each do |run_type|
      memory_query = memory_queries[run_type]
      computers.each do |computer|

        # determining if it is "slow" by comparing to # of standard devs. from
        # the average runtime
        #
        # find least efficient passing instance in current test case commit
        # (may be multiple!) by identifying all from the same computer, then
        # sorting on the appropriate memory usage in ascending order, then take
        # the last
        least_efficient = test_instances.select do |ti|
          ti.computer == computer && ti.passed
        end.sort_by { |ti| ti[memory_query] }.last

        # skip if we can't find the proper runtime
        next unless least_efficient && least_efficient[memory_query]

        # skip if we have no statistics
        next if statistics[run_type][computer].nil? || statistics[run_type][computer].empty?

        # record the slowest as well as the average and standard deviation
        # used to select it
        avg = statistics[run_type][computer][:avg]
        std = statistics[run_type][computer][:std]
        if least_efficient[memory_query] > avg + [threshold * std, min_delta_GB*1e6].max
          to_add = {instance: least_efficient, 
            usage: least_efficient[memory_query], avg: avg, std: std}
          if res[run_type]
            res[run_type][computer] = to_add
          else
            res[run_type] = {computer => to_add}
          end
        end
      end
    end
    res
  end
end
