class Version < ApplicationRecord
  validates_presence_of :number
  validates_uniqueness_of :number

  has_many :test_instances, dependent: :destroy
  has_many :test_cases, through: :test_instances
  has_many :computers, through: :test_instances
  has_many :users, through: :computers

  # NOT DONE
  def status
    pass_count = test_instances.where(passed: true).count
    fail_count = test_instances.where(passed: false).count
    if pass_count > 0 && fail_count > 0
      2
    elsif pass_count > 0
      0
    elsif fail_count > 0
      1
    end
  end

  def failing_instances
    test_instances.where(passed: false)
  end

  # test cases with at least one failing instance
  def some_failing_test_cases
    TestCase.find(failing_instances.pluck(:test_case_id).uniq)
  end

  def passing_instances
    test_instances.where(passed: true)
  end

  # test cases with at least one passing instance
  def some_passing_test_cases
    TestCase.find(passing_instances.pluck(:test_case_id).uniq)
  end

  # array of arrays. First element is array of test cases that pass all
  # instances. Second element is array of test cases that pass and fail at
  # at least once each. Third element is array of test cases that fail all
  # instances.
  def passing_mixed_failing_test_cases
    passing = []
    mixed = []
    failing = []
    pass_some = some_passing_test_cases
    fail_some = some_failing_test_cases
    TestCase.order(:name).each do |test_case|
      if pass_some.include?(test_case) && fail_some.include?(test_case)
        mixed << test_case
      elsif pass_some.include?(test_case)
        passing << test_case
      elsif fail_some.include?(test_case)
        failing << test_case
      end
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
    test_instances.select { |ti| ti.test_case == test_case }
                  .map(&:computer_id).uniq.length
  end

  def status(test_case)
    instances = test_instances.where(test_case: test_case)
    return 3 if instances.empty?
    pass_count = instances.where(passed: true).count
    fail_count = instances.where(passed: false).count
    # all tests pass?
    return 0 if fail_count.zero?
    # all tests fail?
    return 1 if pass_count.zero?
    # mix?
    2
  end
end
