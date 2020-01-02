class TestCaseVersion < ApplicationRecord
  belongs_to :version
  belongs_to :test_case
  has_many :test_instances
  has_many :computers, through: :test_instances

  # STATUS CODES:
  # -1: Untested: no submissions at all
  # 0:  Passing:  at least one submission, all passing
  # 1:  Failing:  at least one submission, all failing
  # 2:  Mixed Checksums: at least two submissions, all passing, different 
  #                      checksums
  # 3:  Mixed:    at least two submissions, some passing, some failing

  @@status_decoder = {
    -1 => :untested,
    0 => :passing,
    1 => :failing,
    2 => :mixed_checksums,
    3 => :mixed
  }

  @@status_encoder = @@status_decoder.invert

  def update_and_save_scalars
    update_submission_count
    update_computer_count
    update_status
    update_last_tested
    save
  end

  def unique_checksums
    self.test_instances.pluck(:checksum).uniq.reject(&:nil?).reject(&:empty?)
  end

  def unique_checksum_count
    unique_checksums.count
  end

  def update_submission_count
    self.submission_count = test_instances.count
  end

  def update_computer_count
    if submission_count == 0
      self.computer_count = 0
    else
      self.computer_count = computers.uniq.count
    end
  end

  def update_last_tested
    self.last_tested = test_instances.pluck(:created_at).max
  end

  def relevant_instances_to_depth(depth: 100, force: false)
    # search query for all instances of this test case that have been tested
    # by the same computers as this test case version back +depth+ versions
    # 
    # By default, return a memoized version if it exists, but force a new 
    # search if +force+ is true
    # 
    # *NOTE* This is sloppy. We are assuming that the +depth+ keyword is not
    # often changed, and it is behaving more like an instance variable since it
    # is shared among several methods. Probably good enough for now, though.
    
    return @relevant_instances if @relevant_instances && !force
    query = test_case.test_instances.where(computer: computers,
      mesa_version: (version.number-depth)...version.number, passed: true).
      includes(:computer)
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
      next unless all_with_runtime.count > 0
      runtimes = all_with_runtime.pluck(runtime_query)

      res[computer] = {avg: nil, std: nil}
      avg = runtimes.inject(:+) / runtimes.count
      res[computer][:avg] = avg

      # calculate sample standard deviation, since we don't use all values
      res[computer][:std] = (runtimes.inject(0) do |res, elt|
        res + (elt - avg)**2
      end / (runtimes.count - 1)) ** (0.5)
    end
    res
  end

  def slow_instances(depth: 100, threshold: 3)
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
    #    TestCaseVersion.where(version: oldest..newest).includes(:computers, :test_instances)
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
        # find slowest in current test case version (may be multiple!) by
        # identifying all from the same computer, then sorting on the
        # appropriate runtime in ascending order, then take the last
        slowest = test_instances.select do |ti|
          ti.computer == computer
        end.sort_by { |ti| ti[runtime_query] }.last

        # skip if we can't find the proper runtime
        next unless slowest && slowest[runtime_query]

        # skip if we have no statistics
        next if statistics[run_type][computer].empty?

        # record the slowest as well as the average and standard deviation
        # used to select it
        avg = statistics[run_type][computer][:avg]
        std = statistics[run_type][computer][:std]
        if slowest[runtime_query] > avg + threshold * std
          to_add = {instance: slowest, time: slowest[runtime_query], avg: avg,
            std: avg}
          if res[run_type]
            res[computer][run_type] = to_add
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
      next unless all_with_usage.count > 0
      usages = all_with_usage.pluck(memory_query)

      res[computer] = {avg: nil, std: nil}
      avg = usages.inject(:+) / usages.count
      res[computer][:avg] = avg

      # calculate sample standard deviation, since we don't use all values
      res[computer][:std] = (usages.inject(0) do |res, elt|
        res + (elt - avg)**2
      end / (usages.count - 1)) ** 0.5
    end
    res
  end

  def inefficient_instances(depth: 100, threshold: 3)
    # Generates hash linking runtime type to lists of memory-hogging instances
    # 
    # "Inefficient" instances are defined to be instances having memory usages
    # that, on a computer-by-computer basis, are more than +threshold+ standard
    # deviations larger than the average, with both statistics computed over
    # the last +depth+ revisions (total revisions, not revisions tested).
    # 
    # *NOTE* to make this fast, load test case versions by including
    # test instances _and_ computers, via something like
    # 
    #    TestCaseVersion.where(version: oldest..newest).includes(:computers, :test_instances)
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
        # find slowest in current test case version (may be multiple!) by
        # identifying all from the same computer, then sorting on the
        # appropriate runtime in ascending order, then take the last
        least_efficient = test_instances.select do |ti|
          ti.computer == computer
        end.sort_by { |ti| ti[memory_query] }.last

        # skip if we can't find the proper runtime
        next unless least_efficient && least_efficient[memory_query]

        # skip if we have no statistics
        next if statistics[run_type][computer].empty?

        # record the slowest as well as the average and standard deviation
        # used to select it
        avg = statistics[run_type][computer][:avg]
        std = statistics[run_type][computer][:std]
        if least_efficient[memory_query] > avg + threshold * std
          to_add = {instance: least_efficient, 
            usage: least_efficient[memory_query], avg: avg, std: avg}
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

  # def slowest_instances_by_computer(runtime_type: :rn)
  #   # Generates a hash that links computer 
  #   runtime_query = TestInstance.runtime_query(runtime_type)
  #   return nil if runtime_query.nil?
  #   res = {}
  #   computers.uniq.each do |computer|
  #     all_with_runtime = test_instances.where(computer: computer).where.not(
  #       runtime_query => nil).order(runtime_query => :desc)
  #     next unless all_with_runtime.count > 0
  #     res[computer] = all_with_runtime.first
  #   end
  #   res
  # end

  def least_efficient_instances_by_computer(run_type: :rn)
    memory_query = TestInstance.memory_query(run_type)
    return nil if memory_query.nil?
    res = {}
    computers.uniq.each do |computer|
      all_with_memory = test_instances.where(computer_id: computer.id).
        where.not(memory_query => nil).order(memory_query => :desc)
      next unless all_with_memory.count > 0
      res[computer] = all_with_memory.first
    end
    res
  end

  def faster_past_instances(depth: 50, percent: 30)
    # structure is a Hash with keys of :total, :rn, and :re. Each key points
    # to a hash with keys of computer names that point to the faster test
    # instances, if there are any that are sufficiently fast
    res = {}
    [:total, :rn, :re].each do |runtime_type|
      res[runtime_type] = {}
      slowest = slowest_instances_by_computer(runtime_type: runtime_type)

      # iterate through each computer's slowest instances, and save the fastest
      # past instance
      slowest.each_pair do |computer, current|
        faster_instances = current.faster_past_instances(
          depth: depth, percent: percent, runtime_type: runtime_type)
        # may not have any, in which case everything is great with this
        # computer.
        unless faster_instances.nil? || faster_instances.empty?
          # there are faster ones. Only hold on to the very fastest. We could
          # hold on to all of them, but if one gets triggered, I imagine MANY
          # will be triggered, so users should rely on the search feature
          res[runtime_type][computer] = {
            current: current,
            better: faster_instances.first
          }
        end
      end
    end
    # destroy empty hashes
    res.keys.each do |key|
      if res[key].empty?
        res.delete(key)
      end
    end
    res
  end

  def more_efficient_past_instances(depth: 50, percent: 10)
    # structure is a Hash with keys of :total, :rn, and :re. Each key points
    # to a hash with keys of computer names that point to the faster test
    # instances, if there are any that are sufficiently fast
    res = {}
    [:rn, :re].each do |run_type|
      res[run_type] = {}
      least_efficient = least_efficient_instances_by_computer(
        run_type: run_type)

      # iterate through each computer's slowest instances, and save the fastest
      # past instance
      least_efficient.each_pair do |computer, current|
        more_efficient_instances = 
          current.more_efficient_past_instances(
            depth: depth, percent: percent, run_type: run_type)
        # may not have any, in which case everything is great with this
        # computer.
        if more_efficient_instances.nil? || more_efficient_instances.empty?
          next
        end
        # there are faster ones. Only hold on to the very fastest. We could
        # hold on to all of them, but if one gets triggered, I imagine MANY
        # will be triggered, so users should rely on the search feature
        res[run_type][computer] = {
          current: current,
          better: more_efficient_instances.first
        }
      end
    end
    # destroy empty hashes
    res.keys.each do |key|
      if res[key].empty?
        res.delete(key)
      end
    end
    res
  end


  def update_status
    # default status: untested
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
    if self.status == @@status_encoder[:passing]
      # collect unique non-nil checksums
      checksums = test_instances.pluck(:checksum).uniq.reject(&:nil?).reject(&:empty?)
      # set to mixed checksums status if more than one distinct checksum
      # found
      self.status = @@status_encoder[:mixed_checksums] if checksums.count > 1
    end
  end
end
