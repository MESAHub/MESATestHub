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

  def slowest_instances_by_computer(runtime_type: :rn)
    runtime_query = TestInstance.runtime_query(runtime_type)
    return nil if runtime_query.nil?
    res = {}
    computers.uniq.each do |computer|
      all_with_runtime = test_instances.where(computer: computer).where.not(
        runtime_query => nil).order(runtime_query => :desc)
      next unless all_with_runtime.count > 0
      res[computer] = all_with_runtime.first
    end
    res
  end

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

  def faster_past_instances(depth: 50, percent: 10)
    # structure is a Hash with keys of :total, :rn, and :re. Each key points
    # to a hash with keys of computer names that point to the faster test
    # instances, if there are any that are sufficiently fast
    res = {}
    [:total, :rn, :re].each do |runtime_type|
      res[runtime_type] = {}
      slowest = slowest_instances_by_computer(runtime_type: runtime_type)

      # iterate through each computer's slowest instances, and save the fastest
      # past instance
      slowest.keys.each do |computer|
        faster_instances = slowest[computer].faster_past_instances(
          depth: depth, percent: percent, runtime_type: runtime_type)
        # may not have any, in which case everything is great with this
        # computer.
        unless faster_instances.nil?
          # there are faster ones. Only hold on to the very fastest. We could
          # hold on to all of them, but if one gets triggered, I imagine MANY
          # will be triggered, so users should rely on the search feature
          res[runtime_type][computer] = faster_instances.first
        end
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
      least_efficient.keys.each do |computer|
        more_efficient_instances = 
          least_efficient[computer].more_efficient_past_instances(
          depth: depth, percent: percent, run_type: run_type)
        # may not have any, in which case everything is great with this
        # computer.
        unless more_efficient_instances.nil?
          # there are faster ones. Only hold on to the very fastest. We could
          # hold on to all of them, but if one gets triggered, I imagine MANY
          # will be triggered, so users should rely on the search feature
          res[run_type][computer] = more_efficient_instances.first
        end
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
