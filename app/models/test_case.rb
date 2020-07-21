class TestCase < ApplicationRecord
  has_many :test_instances, dependent: :destroy
  has_many :test_case_versions, dependent: :destroy
  has_many :test_case_commits, dependent: :destroy
  has_many :computers, through: :test_instances
  has_many :versions, through: :test_instances
  has_many :commits, through: :test_instances
  has_many :users, through: :computers

  validates_presence_of :name

  # this happens to be in reverse alphabetical order, which we exploit heavily
  # in sorting
  def self.modules
    %w[star binary astero]
  end

  def self.ordered_cases(includes: nil)
    if includes.nil?
      self.where.not(module: nil).order(module: :desc, name: :asc)
    else
      self.includes(includes).all
    end
    # res = []
    # self.modules.each do |mod|
    #   res += all_cases.select { |tc| tc.module == mod }.sort do |tc1, tc2|
    #     tc1.name <=> tc2.name
    #   end
    # end
    # res
  end

  def self.current_cases(includes: nil)
    Commit.head.test_cases
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

  def find_test_case_commits(search_params, start_date, end_date)
    # start with search just on dates; can chain other things before we hit
    # the database
    query = {
      commits: {commit_time: start_date..end_date,
                sha: Commit.shas_in_branch(branch: search_params[:branch])}
    }
    unless search_params[:status].nil? or search_params[:status].empty?
      query[:status] = search_params[:status]
    end

    sort_query = ''
    # by default, with most recent commits and instances first
    if search_params[:sort_query].nil? || search_params[:sort_query].empty?
      sort_query = 'commits.commit_time DESC'
    else
      # enforce a valid sort order to prevent SQL injection
      sort_order = search_params[:sort_order] || 'ASC'
      sort_order.upcase!
      unless %w{ASC DESC}.include? sort_order
        sort_order = 'ASC'
      end

      # dictionary between what was passed in (if anything), and what the
      # database understands. This is dumb and clunky.
      # 
      # For most cases, do the desired sorting, and then fall back to
      # descending timestamps (newest first).
      sort_query = case search_params[:sort_query].to_s.downcase
      when "commit" 
        "commits.commit_time #{sort_order}, test_case_commits.created_at DESC"
      when "status" 
        "test_case_commits.status #{sort_order}, test_case_commits.created_at DESC"
      when "date" 
        # these two don't have a real purpose. We could just use the test case
        # commit creation date, but that's not a useful date, and it's not
        # what the column heading says, so this is just redundant for now
        "commits.commit_time #{sort_order}, test_case_commits.created_at DESC"

        # ideally we'd be able to sort on steps/retries, etc., but it's very
        # hard (perhaps impossible?) to create database query that sorts on
        # the first association of a test case commit that is passing, but
        # not a skip case. I'm giving up at this point.
      else
        'commits.commit_time DESC, test_case_commits.created_at DESC'
      end
    end


    test_case_commits.includes(:commit,
      test_instances: {instance_inlists: :inlist_data}).
      where(query).
      order(sort_query).
      page(search_params[:page])
  end

  def find_instances(search_params, start_date, end_date)
    # build this up and then execute only once or twice
    query = {
      commits: {commit_time: start_date..end_date,
                sha: Commit.shas_in_branch(branch: search_params[:branch])}
      }

    return nil if test_instances.joins(:commit).where(query).count == 0

    # which computer/computers to look for results from
    computers = []
    if search_params[:computers]
      computers = Computer.select(:id).where(
        name: search_params[:computers]).pluck(:id)
    else
      # if no computer is selected, only show computer with most computers
      computer_ids = test_instances.joins(:commit).select(:computer_id).where(query).pluck(
        :computer_id)
      frequencies = Hash.new(0)
      computer_ids.each do |id|
        frequencies[id] += 1
      end
      computers = [computer_ids.max_by { |id| frequencies[id] }]
    end

    query[:computer_id] = computers
    unless search_params[:status].nil? || search_params[:status].empty?
      case search_params[:status].to_i
      when 0 then query[:passed] = true
      when 1 then query[:passed] = false
      end
    end

    sort_query = ''
    # by default, with most recent commits and instances first
    if search_params[:sort_query].nil? || search_params[:sort_query].empty?
      sort_query = 'commits.commit_time DESC, test_instances.created_at DESC'
    else
      # enforce a valid sort order to prevent SQL injection
      sort_order = search_params[:sort_order] || 'ASC'
      sort_order.upcase!
      unless %w{ASC DESC}.include? sort_order
        sort_order = 'ASC'
      end

      # dictionary between what was passed in (if anything), and what the
      # database understands. This is dumb and clunky.
      # 
      # For most cases, do the desired sorting, and then fall back to
      # descending timestamps (newest first). Notable exceptions are commit and
      # creation timestamp ordering, which respect user input for ordering.
      sort_query = case search_params[:sort_query].to_s.downcase
      when "commit" 
        "commits.commit_time #{sort_order}, "\
        "test_instances.created_at #{sort_order}"
      when "status" 
        "test_instances.passed #{sort_order}, test_instances.created_at DESC"
      when "date" 
        "test_instances.created_at #{sort_order}"
      when "runtime" 
        "test_instances.runtime_minutes #{sort_order}, "\
        "test_instances.created_at DESC"
      when "ram" 
        "test_instances.mem_rn #{sort_order}, test_instances.created_at DESC"
      when "spec" 
        "test_instances.computer_specification #{sort_order}, "\
        "test_instances.created_at DESC"
      # when "log_rel_run_e_err"
      #   "test_instances.log_rel_run_E_err #{sort_order}, "\
      #   "test_instances.created_at DESC"
      else
        # not one of the special cases, but we need to MAKE SURE THAT THE ENTRY
        # IS A VALID COLUMN, otherwise we are vulnerable to SQL injection
        # attack, where a clever choice of sort_query could drop whole tables
        if TestInstance.column_names.include?(search_params[:sort_query])
          "test_instances.#{search_params[:sort_query]} #{sort_order}, "\
          "test_instances.created_at DESC"
        # if not a default column, maybe it's a custom column
        elsif test_instances.inlist_data.select(:name).distinct.
          include?(search_params[:sort_query])
          "#{search_params[:sort_query].to_s} #{sort_order}, test_instances.created_at DESC"
        else
          # exhausted all possibilites, just default to created_at and hope
          # for the best
          'commits.commit_time DESC, test_instances.created_at DESC'
        end
      end
    end
    test_instances.
      includes(:commit, :instance_inlists, :inlist_data, computer: :user).
      where(query).
      order(sort_query).
      page(search_params[:page])
  end

  def sorted_computers(branch, start_date, end_date)
    commits = Commit.where(sha: Commit.shas_in_branch(branch: branch),
      commit_time: start_date..end_date)
    all_ids = test_instances.where(commit: commits).pluck(:computer_id)
    id_counts = {}
    all_ids.uniq.each do |id|
      id_counts[id] = all_ids.count(id)
    end
    all_ids.sort! { |id1, id2| -(id_counts[id1] <=> id_counts[id2]) }
    Computer.includes(:user).find(all_ids)
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
