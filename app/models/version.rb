class Version < ApplicationRecord
  validates_presence_of :number
  validates_uniqueness_of :number

  has_many :test_instances, dependent: :destroy
  has_many :test_cases, through: :test_instances
  has_many :computers, through: :test_instances
  has_many :users, through: :computers

  paginates_per 10

  # array of arrays. First element is array of test cases that pass all
  # instances. Second element is array of test cases that pass and fail at
  # at least once each. Third element is array of test cases that fail all
  # instances.
  def passing_mixed_failing_test_cases
    passing = []
    mixed = []
    failing = []
    # pass_some = some_passing_test_cases
    # fail_some = some_failing_test_cases
    test_cases.uniq.sort { |t1, t2| t1.name <=> t2.name }.each do |test_case|
      case status(test_case)
      when 0 then passing << test_case
      when 1 then failing << test_case
      when 2 then mixed << test_case
      end
      # if pass_some.include?(test_case) && fail_some.include?(test_case)
      #   mixed << test_case
      # elsif pass_some.include?(test_case)
      #   passing << test_case
      # elsif fail_some.include?(test_case)
      #   failing << test_case
      # end
    end
    [passing, mixed, failing]
  end

  def passing_test_cases
    passing_mixed_failing_test_cases[0]
  end

  def mixed_test_cases
    passing_mixed_failing_test_cases[1]
  end

  def failing_test_cases
    passing_mixed_failing_test_cases[2]
  end

  def computer_specs
    specs = {}
    test_instances.each do |instance|
      spec = instance.computer_specification
      specs[spec] = [] unless specs.include?(spec)
      specs[spec] << instance.computer.name
    end
    specs.each_value(&:uniq!)
    specs
  end

  def statistics
    stats = { passing: 0, mixed: 0, failing: 0 }
    passing, mixed, failing = passing_mixed_failing_test_cases
    stats[:passing] = passing.length
    stats[:mixed] = mixed.length
    stats[:failing] = failing.length
    stats
  end

  def computers_count(test_case)
    unless test_instances.loaded?
      return test_instances.where(test_case: test_case)
                           .pluck(:computer_id).uniq.length
    end
    test_instances.select { |ti| ti.test_case_id == test_case.id }
                  .map(&:computer_id).uniq.length
  end

  def status(test_case)
    if test_instances.loaded?
      # don't do database calls here!
      instances = test_instances.select { |ti| ti.test_case_id == test_case.id }
      pass_count = instances.count { |ti| ti.passed }
      fail_count = instances.count - pass_count
    else
      # test instances not loaded, so just use the database
      instances = test_instances.where(test_case: test_case)
      pass_count = instances.where(passed: true).count
      fail_count = instances.where(passed: false).count
    end
    return 3 if instances.empty?
    # all tests pass?
    return 0 if fail_count.zero?
    # all tests fail?
    return 1 if pass_count.zero?
    # mix?
    2
  end

  # gives overall status, # of passing tests, # of failing tests, and 
  # # of mixed tests
  def summary_status
    pass_count = 0
    fail_count = 0
    mix_count = 0
    test_cases.uniq.each do |test_case|
      case status(test_case)
      when 0 then pass_count += 1
      when 1 then fail_count += 1
      when 2 then mix_count += 1
      end
    end
    status = if pass_count + fail_count + mix_count == 0
               3
             elsif fail_count == 0 && mix_count == 0
               0
             elsif pass_count == 0 && mix_count == 0
               1
             else
               2
             end
    return status, pass_count, fail_count, mix_count
  end

  # update compilation success/fail counts and corresponding compilation status
  def adjust_compilation_status(new_compilation_boolean, computer)
    # Guide: nil = untested (or unreported)
    #          0 = compiles on all systems so far
    #          1 = fails compilation on all systems so far
    #          2 = mixed results
    # this method just keeps this scheme logically consistent when a new report
    # rolls in, but it DOES NOT save the result to the database.
    return if computers.include? computer
    if new_compilation_boolean
      self.compile_success_count += 1
    else
      self.compile_fail_count += 1
    end

    self.compilation_status = if self.compile_fail_count == 0
                                0
                              else
                                if self.compile_success_count == 0
                                  1
                                else
                                  2
                                end
                              end
  end


  def last_tested(test_case=nil)
    if test_instances.loaded?
      if test_case.nil?
        return test_instances.map(&:created_at).max
      else
        return test_instances.select do |ti|
          ti.test_case_id == test_case.id
        end.map(&:created_at).max
      end
    end
    return test_instances.maximum(:created_at) if test_case.nil?
    test_instances.where(test_case: test_case).maximum(:created_at)
  end


  def to_s
    "#{self.number}"
  end

end
