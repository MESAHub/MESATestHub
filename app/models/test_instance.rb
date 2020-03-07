class TestInstance < ApplicationRecord
  @@success_types =  {
    'run_test_string' => 'Test String',
    'run_checksum' => 'Run Checksum',
    'photo_checksum' => 'Photo Checksum'
  }

  @@failure_types = {
    'run_test_string' => 'Test String',
    'final_model' => 'Final Model',
    'run_checksum' => 'Run Checksum',
    'run_diff' => 'Run Diff',
    'photo_file' => 'Missing Photo',
    'photo_checksum' => 'Photo Checksum',
    'photo_diff' => 'Photo Diff',
    'compilation' => 'Compilation'
  }

  @@compilers = %w[gfortran ifort SDK]

  belongs_to :computer
  belongs_to :test_case
  belongs_to :version
  belongs_to :test_case_version
  has_many :test_data, dependent: :destroy
  validates_presence_of :runtime_seconds, :version_id, :computer_id,
                        :test_case_id, :compiler
  # validates_inclusion_of :passed, in: [true, false]
  validates_inclusion_of :success_type, in: @@success_types.keys,
                                        allow_blank: true
  validates_inclusion_of :failure_type, in: @@failure_types.keys,
                                        allow_blank: true
  validates_inclusion_of :compiler, in: @@compilers

  before_save :update_computer_specification, :update_computer_name
  after_save :update_test_case_version
  before_validation :set_test_case_version

  def self.success_types
    @@success_types
  end

  def self.failure_types
    @@failure_types
  end

  def self.compilers
    @@compilers
  end

  def self.runtime_query(runtime_type)
    case runtime_type
    when :rn then :runtime_seconds
    when :re then :re_time
    when :total then :total_runtime_seconds
    else
      return nil      
    end
  end

  def self.memory_query(run_type)
    case run_type
    when :rn then :rn_mem
    when :re then :re_mem
    else
      return nil      
    end
  end

  # list of version numbers with test instances that have failed since a
  # particular date
  def self.failing_versions_since(date)
    Version.find(where(passed: false, created_at: date...Time.now)
      .pluck(:version_id).uniq).sort_by(&:number).reverse
  end

  # list of version numbers with ONLY passing test cases
  def self.passing_versions_since(date)
    # all versions that have at least one passing test instance
    passing_something = Version.find(
      where(passed: true, created_at: date...Time.now)
      .pluck(:version_id).uniq
    ).sort_by(&:number).reverse
    # remove versions that have even one failing test
    passing_something - failing_versions_since(date)
  end

  # list of test cases with instances that failed for a particular version
  # since a particular date
  def self.failing_cases_since(date, version)
    TestCase.find(where(passed: false)
                    .where(created_at: date...Time.now)
                    .where(version: version)
                    .pluck(:test_case_id).uniq).sort_by(&:name)
  end

  def self.assign_checksum_shortcuts(test_instances)
    unique_checksums = test_instances.to_a.map(&:checksum).reject(&:nil?).
      reject(&:empty?).uniq
    # create names that are series of letters. Only make them as long as they 
    # need to be
    max_length = 1
    while 26**max_length < unique_checksums.count
      max_length += 1
    end
    alphabet = ('A'..'Z').to_a
    shortcuts = ['']
    max_length.times do
      shortcuts = shortcuts.product(alphabet).map(&:join)
    end
    encoder = Hash[unique_checksums.zip(shortcuts)]
    encoder[nil] = "-"
    encoder[''] = "-"
    encoder
  end

  def self.get_model_ids(value, model, attribute, method=:find_by)
    if method == :find_by
      model.find_by(attribute.to_sym => value)
    elsif method == :where
      model.where(attribute.to_sym => value).pluck(:id).uniq
    end
  end

  # encapsulates turning a key-value pair to a valid search inquiry.
  # name : string that is the key in a key-value pair for the search query
  # model : the model that actually needs to be searched. Usually this will be 
  #   `self` (TestInstance) when we want to search on attributes of 
  #   TestInstances. Sometimes, though, the search is on an assoiated model.
  #   For instance, searching on the user name. The user name is not stored
  #   in the test instance, and it is not even an association, so instead we
  #   have to search on the Computer associaiton for computers that belong to
  #   a particular user, finds those computer ids, and then searches on the
  #   [existing] attribute `computer_id`
  # attribute : the actual attribute that gets searched in the model. Often
  #   this is similar to the name, but sometimes its more esoteric, as in the
  #   above example, where we have to search for user_id (which we have to find
  #   by the preprocessor argument, see below). Searching for number of threads
  #   (name: 'threads' requires searching on the omp_num_threads attribute.)
  # preprocessor (optional) : a block that takes the input value from the 
  #   search query, which is ALWAYS A STRING, and converts it into the value
  #   that gets searched on in the model. ANY ATTRIBUTE THAT EXPECTS SOMETHING
  #   OTHER THAN A STRING WILL NEED A PREPROCESSOR. For instance, the
  #   preprocessor that searches on number of threads will necessarily convert
  #   the input search value to an integer. Others are more complicated. For
  #   instance, the user name search requires the preprocessor to convert a 
  #   name to a user_id, since that is what we search on the Computer model
  #   for. We do this by using User.find_by_name(), which does exactly the
  #   conversion we want to do.
  class SearchOption
    attr_reader :name
    def initialize(this_name, this_model, this_attribute, &preprocessor)
      @name = this_name
      @model = this_model
      @attribute = this_attribute
      @has_preprocessor = block_given?
      @preprocessor = preprocessor if @has_preprocessor
    end

    def parse_value(value)
      range_matcher = /^\s*(?<min>[^-]+)\s*-\s*(?<max>[^-]+)$/
      m2 = value.match(range_matcher)
      if m2
        # value is a range, so format query appropriately
        if @has_preprocessor
          @preprocessor.call(m2[:min])..@preprocessor.call(m2[:max])
        else
          m2[:min]..m2[:max]
        end
      else
        if @has_preprocessor
          value.split(',').map(&:strip).map(&@preprocessor)
        else
          value.split(',').map(&:strip)
        end
      end
    end

    def get_model_ids(value)
      @model.where(@attribute.to_sym => parse_value(value)).pluck(:id).uniq
    end

    def query_piece(value)
      if @model == TestInstance
        # simple query on TestInstance#where
        {@attribute.to_sym => parse_value(value)}
      else
        # if querying another model, need to convert to from MyModel to
        # my_model_id for query
        key = @model.to_s.gsub(/([A-Z])/, '_\1').gsub(/^_/, '').downcase +
              '_id'
        {key.to_sym => get_model_ids(value)}
      end
    end
  end
      
  def self.parse_runtime(runtime_str)
    # start with no time
    hours = 0
    minutes = 0
    seconds = 0
    m = runtime_str.strip.match(/(?<hours>\d+(\.\d+)?)\s*h+/i)
    hours = m[:hours].to_f if m
    m = runtime_str.strip.match(/(?<minutes>\d+(\.\d+)?)\s*m+/i)
    minutes = m[:minutes].to_f if m
    m = runtime_str.strip.match(/(?<seconds>\d+(\.\d+)?)\s*s+/i)
    seconds = m[:seconds].to_f if m
    if runtime_str.strip.match(/^\d+(\.\d+)?$/)
      seconds = runtime_str.strip.to_f
    end

    # add up times
    minutes += 60 * hours
    seconds + 60 * minutes
  end

  def self.query(query_text)
    query_hash = {}
    # see definition of SearchOption class above; this aids in efficiently
    # building up the search query from many pre-defined searchable options.
    options = [
      SearchOption.new('test_case', TestCase, :name),
      SearchOption.new('version', TestInstance, :mesa_version) do |number|
        number.to_i 
      end,
      SearchOption.new('user', Computer, :user_id) do |user_name|
        User.find_by_name(user_name)
      end,
      SearchOption.new('computer', self, :computer_name),
      # platforms are tied to the computer
      SearchOption.new('platform', Computer, :platform),
      SearchOption.new('platform_version', self, :platform_version),
      # give memory usage in GB, convert to float, and then to kB (how it is in
      # the database)
      SearchOption.new('rn_RAM', self, :rn_mem) do |mem_GB|
        mem_GB.to_f * (1024**2)
      end,
      SearchOption.new('re_RAM', self, :re_mem) do |mem_GB|
        mem_GB.to_f * (1024**2)
      end,
      # runtimes in seconds. Note that runtime_seconds is also aliased to
      # rn_time, so this is the right one
      SearchOption.new('rn_runtime', self, :runtime_seconds) do |rn_runtime|
        parse_runtime(rn_runtime)
      end,
      SearchOption.new('re_runtime', self, :re_time) do |re_runtime|
        parse_runtime(re_runtime)
      end,
      SearchOption.new('runtime', self, :total_runtime_seconds) do |runtime|
        parse_runtime(runtime)
      end,
      SearchOption.new('date', self, :created_at) do |datestring|
        Date.parse(datestring)
      end,
      SearchOption.new('datetime', self, :created_at) do |datetimestring|
        DateTime.parse(datetimestring)
      end,
      SearchOption.new('threads', self, :omp_num_threads) do |n_threads|
        n_threads.to_i
      end,
      SearchOption.new('compiler', self, :compiler),
      SearchOption.new('compiler_version', self, :compiler_version),
      SearchOption.new('passed', self, :passed) do |passage_status|
        if passage_status =~ /f$|false$/i
          false
        elsif passage_status =~ /t$|true$/i
          true
        end
      end
    ]
    option_names = options.map(&:name)
    options_hash = Hash[option_names.zip(options)]
    reconstructed_query = ''
    failed_requirements = []
    res = TestInstance.where(nil)
    requirement_matcher = /^(?<key>[^:"']+):\s+("|')?(?<value>[^'"]+)("|')?$/
    query_text.split(';').map(&:strip).each do |requirement|
      # puts "checking string #{requirement}"
      m1 = requirement.match(requirement_matcher)
      
      unless m1 && option_names.include?(m1[:key])
        # poorly formed query requirement; add to failure list to report back
        # later
        # puts "didn't find any valid options"
        failed_requirements << requirement
        next
      end
      # puts "found key: #{m1[:key]} and value: #{m1[:value]}"
      query_hash[m1[:key]] = m1[:value]
    end

    # now have key-value pairs, values may be ranges. Reach out to each
    # SearchOption to actually get query, and shove each into a where call.
    # ActiveRecord is lazy and will compress these all into a single search
    # when it is needed.
    query_hash.each_pair do |key, value|
      res = res.where(options_hash[key].query_piece(value))
    end
    # res
    return [res.order(mesa_version: :desc, created_at: :desc).
      includes(:test_case, :version, computer: :user), failed_requirements]
  end

  def update_computer_name
    self.computer_name ||= computer.name
  end

  def update_computer_specification
    self.computer_specification ||= generate_computer_specification
  end

  def generate_computer_specification
    spec = ''
    spec += computer.platform + ' ' if computer.platform
    spec += platform_version + ' ' if platform_version
    spec += compiler + ' ' if compiler
    spec += compiler_version if compiler_version
    spec = 'no specificaiton' if spec.empty?
    spec.strip
  end

  def data(name)
    test_data.where(name: name).order(updated_at: :desc).first.value
  end

  def set_data(name, new_val)
    test_data.where(name: name).order(updated_at: :desc).first.value = new_val
  end

  def to_minutes(num)
    num.to_f / 60.0
  end

  def kB_to_GB(mem_kB)
    mem_kB.to_f / (1024**2)
  end

  # alias for convenience and inconsistent naming (sorry)
  def rn_time
    runtime_seconds 
  end

  def total_runtime_minutes
    to_minutes(total_runtime_seconds)
  end

  def rn_time_minutes
    to_minutes(rn_time)
  end

  def re_time_minutes
    to_minutes(re_time)
  end

  def rn_mem_GB
    kB_to_GB(rn_mem)
  end

  def re_mem_GB
    kB_to_GB(re_mem)
  end

  def set_computer_name(user, new_computer_name)
    new_computer = user.computers.where(name: new_computer_name).first
    if new_computer.nil?
      errors.add :computer_id, 'Could not find computer with name ' \
        "\"#{new_computer_name}\"."
    else
      self.computer = new_computer
      self.computer_name = new_computer.name
      self.computer_specification = generate_computer_specification
    end
  end

  def set_computer(user, computer)
    if computer.user == user
      self.computer = computer
    else
      errors.add :computer_id, "Computer #{computer.name} does not belong to "\
                               "user #{user.name}."
    end
  end

  # meant to ease transition from mesa_version to Version model.
  def update_version(do_save=false)
    # don't do anything if versions are both set (or if we are helpless)
    return if version_id && mesa_version
    return unless version_id || mesa_version
    # conditionally update the integer mesa_version
    if version_id
      self.mesa_version ||= version.number
    # conditionally update the version
    else
      self.version = Version.find_or_create_by(number: mesa_version)
    end
    save if do_save
  end

  # still useful to have direct access to mesa_version for sorting purposes
  def mesa_version
    return super if super
    self.update_attributes(mesa_version: version.number)
    super
  end  

  def set_test_case_name(new_test_case_name, mod, version_number=10000)
    new_test_case = TestCase.find_by(name: new_test_case_name)
    if new_test_case.nil?
      # no test case found, so just make one up
      # this test case will have NO EXTRA DATA ASSOCIATED WITH IT
      # at time of this edit (November 22, 2017), the data features is not in
      # use, but this may need to be revisited
      new_test_case = TestCase.create(
        name: new_test_case_name,
        module: mod,
        version_added: version_number
      )
      new_test_case.update_version_created
      # old behavior: scuttle the saving process
      # errors.add :test_case_id,
      #            'Could not find test case with name "' + new_test_case_name +
      #            '".'
    end
    self.test_case = new_test_case
  end

  # full text for passage status
  def passage_status
    if passed
      if success_type
        "PASS: #{TestInstance.success_types[success_type]}"
      else
        "PASS"
      end
    else
      if failure_type
        "FAIL: #{TestInstance.failure_types[failure_type]}"
      else
        "FAIL"
      end
    end
  end

  def set_test_case_version
    return if test_case_version
    candidate = TestCaseVersion.find_by(
      version: version, test_case: test_case
    )
    if candidate
      # found it!
      self.test_case_version = candidate
    else
      # doesn't exist, so make a new one
      # this one doesn't have status and other values set; this should
      # happen when `update_test_case_version` is called
      self.test_case_version = TestCaseVersion.create!(
        version_id: version.id,
        test_case_id: test_case.id
      )
    end
  end

  def update_test_case_version
    # make sure we have a test_case version
    set_test_case_version unless self.test_case_version_id

    # tell the test_case_version to update itself
    test_case_version.update_and_save_scalars
  end

  # overridden to get user names, computer names, and other details
  def as_json(options)
    {
      test_case: test_case.name,
      version: mesa_version,
      passed: passed,
      success_type: success_type,
      failure_type: failure_type,
      computer: computer_name,
      user: computer.user.name,
      datetime: created_at,
      platform: computer.platform,
      platform_version: platform_version,
      rn_runtime: rn_time,
      re_runtime: re_time,
      runtime: total_runtime_seconds,
      rn_mem: rn_mem_GB,
      re_mem: re_mem_GB,
      threads: omp_num_threads,
      compiler: compiler,
      compiler_version: compiler_version,
      summary_text: summary_text,
      checksum: checksum
    }
  end

  def recent_passing_with_similar_specs(depth: 50)
    TestInstance.where(
      mesa_version: (mesa_version - depth)...mesa_version,
      computer_id: computer_id,
      omp_num_threads: omp_num_threads,
      compiler: compiler,
      compiler_version: compiler_version,
      test_case_id: test_case_id,
      passed: true
    )
  end

  # get fastest test instances from past submissions from same computer with
  # same compiler and thread count for which this runtime is `percent` longer
  # 
  # `depth` is how far back in versions to look, and `runtime_type` is one of
  # :rn, :re, and :total
  def faster_past_instances(depth: 50, percent: 10.0, runtime_type: :rn)
    runtime_query = TestInstance.runtime_query(runtime_type)
    return nil unless runtime_query
    this_runtime = self.send(runtime_query)

    # old instances don't have all runtimes
    # also skip really short runtimes since they are more unpredictable
    return nil if (this_runtime.nil? or this_runtime < 60)

    # longest allowable runtime set by new/old = 100% + `percent`%
    max_old_runtime = this_runtime * ( 1.0 / (1.0 + percent / 100.0))

    # do query, starting with "similar" past instances
    recent_passing_with_similar_specs(depth: depth).where(
      runtime_query => 1e-2..max_old_runtime
    ).order(runtime_query)
  end

  # get past test instances from the same computer, compiler, and thread count
  # for which the current RAM usages is `percent` percent larger
  #
  # `depth` is how far back in versions to look, and `runtime_type` is one of
  # :rn, :re, and :total
  def more_efficient_past_instances(depth: 50, percent: 10.0, run_type: :rn)
    # get right method to get desired memory usage (rn or re)
    memory_query = TestInstance.memory_query(run_type)
    return nil unless memory_query

    # retrieve memory, ensure it exists or bail (also bail for small RAM)
    this_mem_usage = self.send(memory_query)
    return nil if (this_mem_usage.nil? || this_mem_usage < 1024**2)

    # largest allowable memory usage is set by new/old = 100% + `percent`%
    max_old_mem = this_mem_usage * (1.0 / (1.0 + percent / 100.0))

    # do query, starting with "similar past instances"
    recent_passing_with_similar_specs(depth: depth).where(
      memory_query => 1e-2..max_old_mem
    ).order(memory_query)
  end

  # make test_data easier to access as if they were attributes
  def method_missing(method_name, *args, &block)
    if test_case.data_names.include? method_name.to_s
      data(method_name.to_s)
    elsif (test_case.data_names.include? method_name.to_s.chomp('=') &&
           args.length > 0)
      set_data(method_name.to_s.chomp('='), args[0])
    else
      super(method_name, *args, &block)
    end
  end
    
end
