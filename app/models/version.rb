class Version < ApplicationRecord
  validates_presence_of :number
  validates_uniqueness_of :number

  has_many :test_case_versions, dependent: :destroy
  has_many :test_instances, through: :test_case_versions, dependent: :destroy

  has_many :test_cases, through: :test_case_versions
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

  def passing_mixed_failing_checksums_other_test_case_versions
    @passing = []
    @mixed = []
    @failing = []
    @checksums = []
    @other = []
    # pass_some = some_passing_test_cases
    # fail_some = some_failing_test_cases
    test_case_versions.uniq.sort do |t1, t2|
      t1.test_case.name <=> t2.test_case.name
    end.each do |tcv|
      case tcv.status
      when 0 then @passing << tcv
      when 1 then @failing << tcv
      when 2 then @checksums << tcv
      when 3 then @mixed << tcv
      else
        @other << tcv
      end
      # if pass_some.include?(test_case) && fail_some.include?(test_case)
      #   mixed << test_case
      # elsif pass_some.include?(test_case)
      #   passing << test_case
      # elsif fail_some.include?(test_case)
      #   failing << test_case
      # end
    end
    [@passing, @mixed, @failing, @checksums, @other]
  end


  def passing
    @passing || passing_mixed_failing_checksums_other_test_case_versions[0]
  end

  def mixed
    @mixed || passing_mixed_failing_checksums_other_test_case_versions[1]
  end

  def failing
    @failing || passing_mixed_failing_checksums_other_test_case_versions[2]
  end

  def checksums
    @checksums || passing_mixed_failing_checksums_other_test_case_versions[3]
  end

  def other
    @other || passing_mixed_failing_checksums_other_test_case_versions[-1]
  end

  def computer_specs
    specs = {}
    test_instances.each do |instance|
      spec = instance.computer_specification
      specs[spec] = [] unless specs.include?(spec)
      specs[spec] << instance.computer_name
    end
    specs.each_value(&:uniq!)
    specs
  end

  def statistics
    { passing: test_case_versions.where(status: 0).count,
      mixed: test_case_versions.where(status: 3).count,
      failing: test_case_versions.where(status: 1).count,
      checksums: test_case_versions.where(status: 2).count,
      other: test_case_versions.where(status: -1).count
    }
    # passing, mixed, failing = passing_mixed_failing_test_cases
    # stats[:passing] = passing.length
    # stats[:mixed] = mixed.length
    # stats[:failing] = failing.length
    # stats
  end

  def computers_count(test_case)
    test_case_versions.pluck(:computer_count).max
  end

  def status(test_case)
    TestCaseVersion.find_or_create_by(version: self, test_case: test_case).status
  end

  def diff_status(test_case)
    if test_instances.loaded?
      test_case_instances = test_instances.select do |ti|
        ti.test_case_id == test_case.id
      end
      # don't do the database call
      diff_count = test_case_instances.select { |ti| ti.diff == 1 }.length
      # 1 = at least one instance ran a diff
      return 1 if diff_count > 0
      no_diff_count = test_case_instances.select { |ti| ti.diff == 0 }.length
      # 0 = literally zero tests did a diff, and we know it
      return 0 if no_diff_count == test_case_instances.length
    else
      diff_count = test_instances.where(test_case: test_case, diff: 1).count
      # 1 = at least one instance ran a diff
      return 1 if diff_count > 0
      no_diff_count = test_instances.where(test_case: test_case, diff: 0).count
      total_count = test_instances.where(test_case: test_case).count
      # 0 = literally zero tests did a diff, and we know it
      return 0 if no_diff_count == total_count
    end
    # still here? Then no tests report having run diff, but at least one
    # didn't report what it was
    return 2
  end



  # gives overall status, # of passing tests, # of failing tests, and 
  # # of mixed tests
  def summary_status
    pass_count = 0
    fail_count = 0
    mix_count = 0
    checksum_count = 0
    other_count = 0
    test_case_versions.each do |tcv|
      case tcv.status
      when 0 then pass_count += 1
      when 1 then fail_count += 1
      when 2 then checksum_count += 1
      when 3 then mix_count += 1
      else
        other_count += 1
      end
    end
    status = if other_count.positive?
               -1 # something weird happened with at least one test, scream about this
             elsif mix_count.positive?
               3  # at least one mixed results test. This is important
             elsif checksum_count.positive?
               2  # no mixed tests, but at least one with inconsistent checksums
             elsif fail_count.positive?
               1  # no checksum or mixed problems, but one test fails everyone
             elsif pass_count.positive?
               0  # no troublesome tests at all, we're passing and good!
             else
               -2 # no tests of any kind; we didn't test anything
             end
    # status = if [pass_count, fail_count, mix_count, checksum_count, other_count].sum.zero?
    #            3  # not tested
    #          elsif [fail_count, mix_count, checksum_count, other_count].sum.zero?
    #            0  # all passing
    #          elsif [mix_count, checksum_count, other_count].sum.zero?
    #            1  # some tests fail on all computers; call this failing
    #          elsif [checksum_count, other_count].sum.zero?].sum.zero?
    #            2  
    #          end
    return status, pass_count, fail_count, mix_count, checksum_count, other_count
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
    test_case_versions.pluck(:last_tested).max
  end


  def to_s
    "#{self.number}"
  end

end
