class TestCase < ApplicationRecord
  has_many :test_instances, dependent: :destroy
  has_many :test_case_versions, dependent: :destroy
  has_many :test_case_commits, dependent: :destroy
  has_many :computers, through: :test_instances
  has_many :versions, through: :test_instances
  has_many :commits, through: :test_instances
  has_many :users, through: :computers

  validates_presence_of :name

  def self.modules
    %w[star binary astero]
  end

  validates_inclusion_of :module, in: TestCase.modules, allow_blank: true

  # def self.find_by_version(version = :all)
  #   return TestCase.all.order(:name) if version.to_s.to_sym == :all
  #   search_version = version == :latest ? versions.max : version
  #   # TestInstance is indexed on mesa version, so we get those in constant
  #   # time, then back out unique Test Cases. This is usually used to get
  #   # data for index, so eagerly load instances to get at status without
  #   # hitting database for a ton more queries
  #   TestCase.includes(:test_instances).find(
  #     TestInstance.where(
  #       mesa_version: search_version
  #     ).pluck(:test_case_id).uniq
  #   ).sort { |a, b| (a.name <=> b.name) }
  # end

  # def self.version_statistics(test_cases, version)
  #   stats = { passing: 0, mixed: 0, failing: 0 }
  #   test_cases.each do |test_case|
  #     case test_case.version_status(version)
  #     when 0 then stats[:passing] += 1
  #     when 1 then stats[:failing] += 1
  #     when 2 then stats[:mixed] += 1
  #     end
  #   end
  #   stats
  # end

  # def self.version_computer_specs(test_cases, version)
  #   specs = {}
  #   test_cases.each do |test_case|
  #     test_case.version_instances(version).each do |instance|
  #       spec = instance.computer_specification
  #       specs[spec] = [] unless specs.include?(spec)
  #       specs[spec] << instance.computer.name
  #     end
  #   end
  #   specs.each_value(&:uniq!)
  #   specs
  # end

  # for tight space when we need the name
  def short_name
    return name if name.length <= 20
    name[0,17] + '...'
  end

  def find_test_case_commits(search_params)
    # start with blank query that we can chain from, but be sure to include
    # commits with whatever we come up with
    res = test_case_commits.includes(:commit)
    if search_params[:start_date] || search_params[:end_date]
      unless search_params[:start_date] && search_params[:end_date]
        all_dates = test_case_commits.pluck('created_at')
      end
      start_date = search_params[:start_date] || all_dates.min
      end_date = search_params[:end_date] || all_dates.max
      res = res.where(created_at: start_date..end_date)
    end
    if search_params[:status]
      res = res.where(status: status)
    end
    sort_query = search_params[:sort_query] || :created_at
    sort_order = search_params[:sort_order] || :desc
    res.order(sort_query => sort_order).page(search_params[:page])
  end

  def find_instances(search_params)
    start_date = search_params[:start_date] || test_instances.order(
      created_at: :asc).first.created_at
    end_date = search_params[:end_date] || test_instances.order(
      created_at: :desc).first.created_at
    res = test_instances.includes(:commit).where(created_at: start_date..end_date)

    # which computer/computers to look for results from
    computers = []
    if search_params[:computers]
      computers = Computer.where(name: search_params[:computers]).pluck(:id)
    else
      # if no computer is selected, only show computer with most computers
      computer_ids = res.pluck(:computer_id)
      frequencies = Hash.new(0)
      computer_ids.each do |id|
        frequencies[id] += 1
      end
      computers = [computer_ids.max_by { |id| frequencies[id] }]
    end

    res.where(computer_id: computers)
    sort_query = search_params[:sort_query] || :created_at
    sort_order = search_params[:sort_order] || :desc
    res.order(sort_query => sort_order).page(search_params[:page])
  end

  # list of version numbers with test instances that have failed since a
  # particular date (handled by TestInstance... unclear where this should live)
  def self.failing_versions_since(date)
    TestInstance.failing_versions_since(date)
  end

  # list of version numbers with test instances that have passed since (with
  # none failing) a particular date (handled by TestInstance... unclear where
  # this should live)
  def self.passing_versions_since(date)
    TestInstance.passing_versions_since(date)
  end

  # list of test cases with instances that failed for a particular version
  # since a particular date (handled by TestInstance... unclear where this
  # should live)
  def self.failing_cases_since(date, version)
    TestInstance.failing_cases_since(date, version)
  end

  def last_tested
    return test_instances.maximum(:created_at) unless test_instances.loaded?
    test_instances.map(&:created_at).max
  end

  alias last_tested_date last_tested

  def last_test_status
    return 3 if test_instances.empty?
    test_instances.where(created_at: last_tested_date).first.passed ? 0 : 1
  end

  # def mesa_versions
  #   test_instances.pluck(:mesa_version).uniq.sort.reverse
  # end

  # instances that were run for a particular version
  def version_instances(version, limit = nil)
    return test_instances if version == :all
    # hit the database directly if needed
    unless test_instances.loaded?
      if limit
        return test_instances.includes(:computer)
                             .where(version: version)
                             .order(created_at: :desc)
                             .limit(limit)
      else                             
        return test_instances.includes(:computer)
                             .where(version: version)
                             .order(created_at: :desc)
      end
    end
    # instances already loaded? avoid hitting the database
    res = test_instances.select { |t| t.version_id == version.id }
                        .sort { |a, b| -(a.created_at <=> b.created_at) }
    if limit
      res.first(limit)
    else
      res
    end
  end

  # computers that have tested this case for a particular version
  def version_computers(version, limit = nil)
    version_instances(version, limit).map(&:computer).uniq
  end

  def version_status(version)
    return last_version_status if version == :all
    these_instances = version_instances(version)
    return 3 if these_instances.empty?
    passing_count = 0
    failing_count = 0
    if test_instances.loaded?
      passing_count = these_instances.select(&:passed).length
      failing_count = these_instances.reject(&:passed).length
    else
      passing_count = these_instances.where(passed: true).count
      failing_count = these_instances.where(passed: false).count
    end
    # success by default if we have at least one instance and no failures
    return 0 unless failing_count > 0
    # at least one failing, if also one passing, send back 2 (mixed). Otherwise
    # send back 1 (failing)
    passing_count > 0 ? 2 : 1
  end

  # def version_computers_count(version)
  #   unless test_instances.loaded?
  #     return version_instances(version).pluck(:computer_id).uniq.length
  #   end
  #   version_instances(version).map(&:computer_id).uniq.length
  # end

  def last_version
    return test_instances.maximum(:mesa_version) unless test_instances.loaded?
    test_instances.map(&:mesa_version).max
  end

  def last_version_status
    version_status(last_version)
  end

  # ease transition from versions being hard coded to using new Version model
  def update_version_created
    return if version_id
    return unless version_added
    new_version = Version.find_or_create_by(number: version_added)
    update_attributes(version_id: new_version.id)
    new_version.number
  end


end
