class Version < ApplicationRecord
  validates_presence_and_uniqueness_of :number

  has_many :test_instances, dependent: :destroy
  has_and_belongs_to_many :test_cases, through: :test_instance
  has_and_belongs_to_many :computers, through: :test_instance
  has_and_belongs_to_many :users, through: :computers

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
    TestCase.find(passing_instances.pluck(:test_case_id).uniz)
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
end
