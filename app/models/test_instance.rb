class TestInstance < ApplicationRecord
  @@success_types =  {
    'run_test_string' => 'Test String',
    'run_checksum' => 'Run Checksum',
    'photo_checksum' => 'Photo Checksum',
    'skip' => 'Skipped'
  }

  @@failure_types = Hash.new('Unknown')

  @@failure_types.merge!({
    'run_test_string' => 'Test String',
    'final_model' => 'Final Model',
    'run_checksum' => 'Run Checksum',
    'run_diff' => 'Run Diff',
    'photo_file' => 'Missing Photo',
    'photo_checksum' => 'Photo Checksum',
    'photo_diff' => 'Photo Diff',
    'compilation' => 'Compilation',
    'stderr' => 'Stderr (mesa_error?)'
  })

  @@compilers = %w[gfortran ifort SDK]

  belongs_to :computer
  belongs_to :test_case

  # git era
  belongs_to :commit
  belongs_to :test_case_commit
  belongs_to :submission

  has_many :instance_inlists, dependent: :destroy
  has_many :inlist_data, through: :instance_inlists

  paginates_per 50

  validates_presence_of :computer_id, :test_case_id, :compiler
  validates_inclusion_of :success_type, in: @@success_types.keys,
                                        allow_blank: true
  validates_inclusion_of :failure_type, in: @@failure_types.keys,
                                        allow_blank: true
  validates_inclusion_of :compiler, in: @@compilers

  before_validation :set_tcc
  before_save :update_computer_specification, :update_computer_name
  after_save :update_tcc

  scope :full, -> { where(run_optional: true) }
  scope :partial, -> { where(run_optional: false) }

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
    when :rn then :mem_rn
    when :re then :mem_re
    else
      return nil      
    end
  end

  # version of +new+ that is more useful for submissions
  def self.submission_new(instance_params, submission)
    # first get a hold of the test case itself
    test_case = TestCase.find_by(name: instance_params[:test_case],
                                 module: instance_params[:module])
    # bail if parameters were crummy for some reason
    return nil if test_case.nil?

    # create instance from "good" parameters
    # slick way to start things off assuming the params passed to the
    # submission API match the name and type of those in the db. May need to be
    # updated as more junk is added to the test output, and attributes may need
    # to be set manually if naming conventions between testhub and mesa diverge
    instance = new(instance_params.reject do |key|
      ['test_case', 'module', 'inlists', 'outcome'].include? key 
    end)

    # other important details that we can't get directly from the params
    instance.test_case = test_case
    instance.submission = submission
    instance.commit = submission.commit
    instance.computer = submission.computer
    instance.platform_version = submission.platform_version
    instance.passed = instance_params['outcome'] =~ /pass/ ? true : false

    # remove success type for failing instance
    instance.success_type = nil unless instance.passed

    # these are from +testhub.yml+ of installation (in base MESA_DIR after
    # installation), but are forwarded from the submission
    instance.compiler = submission.compiler
    instance.compiler_version = submission.compiler_version
    instance.sdk_version = submission.sdk_version
    instance.math_backend = submission.math_backend

    # initialize these now; will sum up from individual inlists later
    instance.runtime_minutes = 0
    instance.steps = 0
    instance.retries = 0
    instance.redos = 0
    instance.solver_iterations = 0
    instance.solver_calls_failed = 0
    instance.solver_calls_made = 0

    # now we need to go through the individual inlists, create them, and
    # associate them with the test instance
    if instance_params[:inlists]
      instance_params[:inlists].each do |inlist_params|
        new_inlist = instance.instance_inlists.build(
          inlist_params.reject do |key|
            ['extra_testhub_names', 'extra_testhub_vals'].include? key
          end
        )
        # optionally build on extra data to the inlist
        if inlist_params['extra_testhub_names'] &&
           inlist_params['extra_testhub_vals']
          inlist_params['extra_testhub_names'].zip(
            inlist_params['extra_testhub_vals']).each do |datum_name, datum_val|
            new_inlist.inlist_data.build(name: datum_name, val: datum_val)
          end
        end
      end

      # calculate summed values from all inlists
      instance.instance_inlists.each do |inlist|
        instance.runtime_minutes += inlist.runtime_minutes if inlist.runtime_minutes
        instance.steps += inlist.steps if inlist.steps
        instance.retries += inlist.retries if inlist.retries
        instance.redos += inlist.redos if inlist.redos
        instance.solver_iterations += inlist.solver_iterations if inlist.solver_iterations
        instance.solver_calls_failed += inlist.solver_calls_failed if inlist.solver_calls_failed
        instance.solver_calls_made += inlist.solver_calls_made if inlist.solver_calls_made
        # adding linear quantities; will take log at the end
      end
    end

    # test case commit automatically set by +#set_tcv_or_tcc+ at validation
    instance
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
  # ranged : whether or not the option can be searched on a range. For
  #   instance, a datetime or memory used make sense to search over a range,
  #   while a user name does not. Default is false.
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
    attr_reader :ranged
    def initialize(this_name, this_model, this_attribute, ranged=false, 
                   &preprocessor)
      @name = this_name
      @model = this_model
      @attribute = this_attribute
      @ranged = ranged
      @has_preprocessor = block_given?
      @preprocessor = preprocessor if @has_preprocessor
    end

    # need to account for values that have dashes, like computer names or
    # dates formatted as YYYY-MM-DD... currently broken
    def parse_value(value)
      # catch tricky situations when ranged objects themselves have values with
      # hyphens (mostly dates)
      hyphen_count = value.count('-')
      if ranged and hyphen_count > 1
        parse_hyphen_range(value)
      else
        # simple range or collection
        range_matcher = /^\s*(?<min>[^-]+)\s*-\s*(?<max>[^-]+)$/
        m2 = value.match(range_matcher)
        if m2 && ranged
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
    end

    def parse_hyphen_range(value)
      hyphen_count = value.count('-')
      if hyphen_count.modulo(2) == 1
        # odd number of hyphens, so treat middle one as range indicator,
        # others are part of literal to be fed to preprocessor (or preserved)
        rank = 0 # tracks which hyphen we have are looking for
        range_rank = hyphen_count / 2 # integer division to the rescue
        range_position = nil # this will hold the index of the range hyphen
        position = 0
        value.each_char do |char|
          if char == '-'
            # found a hyphen! is it the correct one?
            if rank == range_rank
              # it is! save its position and stop looping
              range_position = position
              break
            end

            # found one, but it's not the range one, so up
            rank += 1
          end

          # always update position (crummy enumerable... should couple these)
          position += 1
        end
        min = value[(0...range_position)].strip
        max = value[((range_position + 1)..-1)].strip
        if @has_preprocessor
          @preprocessor.call(min)..@preprocessor.call(max)
        else
          min..max
        end
      else
        # even number of hyphens? Uh... return nil, I guess?
        nil
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

  def self.split_query(query_text)
    # split on colons, but note that the divider separates keys from values,
    # and not key-value pairs from each other. So we will have an array that
    # looks like [key1, val1 key2, val2 key3, ... valn-1 keyn, valn]
    split_up = query_text.split(':')

    # first key is trivial
    keys = [split_up[0].strip.downcase]
    values = []

    # now go through interior elements to split up keys and values
    split_up[(1..-2)].each do |piece|
      m = piece.match(/(?<val>^.*)[\s,;]+(?<next_key>\w+$)/)
      values << m[:val].gsub(/['"]/, '').sub(/[\s,;]+$/, '').strip
      keys << m[:next_key].strip.downcase
    end

    # last element is the last value
    values << split_up[-1].gsub(/['"]/, '').sub(/[\s,;]+$/, '').strip

    # return as a hash
    # need an error here if keys are not unique
    Hash[keys.zip(values)]
  end    

  def self.query(query_text)
    query_hash = {}
    # see definition of SearchOption class above; this aids in efficiently
    # building up the search query from many pre-defined searchable options.
    options = [
      SearchOption.new('test_case', TestCase, :name),
      # SearchOption.new('version', TestInstance, :mesa_version, true) do |number|
        # number.to_i 
      # end,
      SearchOption.new('commit', Commit, :short_sha) do |sha|
        sha[(0..7)]
      end,
      SearchOption.new('commit_datetime', Commit, :commit_time, true) do |datetime|
        Date.parse(datetime)
      end,
      SearchOption.new('user', Computer, :user_id) do |user_name|
        User.find_by_name(user_name)
      end,
      SearchOption.new('computer', self, :computer_name),
      # platforms are tied to the computer
      SearchOption.new('platform', Computer, :platform),
      SearchOption.new('platform_version', self, :platform_version, true),
      # give memory usage in GB, convert to float, and then to kB (how it is in
      # the database)
      SearchOption.new('rn_RAM', self, :mem_rn, true) do |mem_GB|
        mem_GB.to_f * (1024**2)
      end,
      SearchOption.new('re_RAM', self, :mem_re, true) do |mem_GB|
        mem_GB.to_f * (1024**2)
      end,
      # runtimes now in minutes. Meaning less clear as this is reported by
      # test cases themselves
      SearchOption.new('runtime', self, :total_runtime_minutes, true),
      SearchOption.new('date', self, :created_at, true) do |datestring|
        Date.parse(datestring)
      end,
      SearchOption.new('datetime', self, :created_at, true) do |datetimestring|
        DateTime.parse(datetimestring)
      end,
      SearchOption.new('threads', self, :omp_num_threads, true) do |n_threads|
        n_threads.to_i
      end,
      SearchOption.new('compiler', self, :compiler),
      SearchOption.new('compiler_version', self, :compiler_version, true),
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
    failed_requirements = []
    res = TestInstance.where(nil)
    # requirement_matcher = /^(?<key>[^:"']+):\s*("|')?(?<value>[^'"]+)("|')?$/
    # query_text.split(';').map(&:strip).each do |requirement|
    #   # puts "checking string #{requirement}"
    #   m1 = requirement.match(requirement_matcher)
      
    #   unless m1 && option_names.include?(m1[:key])
    #     # poorly formed query requirement; add to failure list to report back
    #     # later
    #     # puts "didn't find any valid options"
    #     failed_requirements << requirement
    #     next
    #   end
    #   # puts "found key: #{m1[:key]} and value: #{m1[:value]}"
    #   query_hash[m1[:key]] = m1[:value]
    # end
    query_hash = split_query(query_text)
    query_hash.keys.each do |key|
      unless option_names.include?(key)
        failed_requirements << key
      end
    end

    # obliterate ill-formed search keys
    failed_requirements.each {|key| query_hash.delete(key) }

    puts '#########################'
    puts 'query:'
    puts query_hash
    puts '#########################'
    
    # now have key-value pairs, values may be ranges. Reach out to each
    # SearchOption to actually get query, and shove each into a where call.
    # ActiveRecord is lazy and will compress these all into a single search
    # when it is needed.
    query_hash.each_pair do |key, value|
      res = res.where(options_hash[key].query_piece(value))
      puts "adding to query:"
      puts options_hash[key].query_piece(value)
    end

    res = res.where.not(commit_id: nil)
    # res
    return [res.includes(:test_case, :test_case_commit, :commit, computer: :user).
      order('commits.commit_time DESC, test_instances.created_at DESC'), failed_requirements]
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
    if sdk_version
      spec += "SDK #{sdk_version} "
      spec += "#{math_backend} " if math_backend
    else
      spec += compiler + ' ' if compiler
      spec += compiler_version if compiler_version
    end
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
    kB_to_GB(mem_rn)
  end

  def re_mem_GB
    kB_to_GB(mem_re)
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

  def set_test_case_name(new_test_case_name, mod)
    new_test_case = TestCase.find_by(name: new_test_case_name, module: mod)
    if new_test_case.nil?
      # no test case found, so just make one up
      # this test case will have NO EXTRA DATA ASSOCIATED WITH IT
      # at time of this edit (November 22, 2017), the data features is not in
      # use, but this may need to be revisited
      # Update: no one cares (February 22, 2020)
      new_test_case = TestCase.create(
        name: new_test_case_name,
        module: mod,
      )
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

  def data_names
    inlist_data.load unless inlist_data.loaded?
    test_data.pluck(:name).uniq
  end

  def get_inlist_data(inlist_name, *data_names)
    instance_inlists.load unless instance_inlists.loaded?

    # fix stupid runtime/runtime_minutes thing. This is hideous
    data_names.map! { |col| col == 'runtime' ? 'runtime_minutes' : col }

    # find inlist with the right name. This should give an array
    inlist = nil
    instance_inlists.each do |instance_inlist|
      if (instance_inlist.inlist == inlist_name)
        inlist = instance_inlist
        break
      end
    end

    # bail out if we got a bad inlist
    return nil if inlist.nil?

    if data_names.length == 1
      if InstanceInlist.column_names.include? data_names[0]
        inlist[data_names[0].to_sym]
      else
        data = inlist.inlist_data.select { |datum| datum.name == data_names[0] }
        return nil if data.empty?
        data.first.val
      end
    else
      data_names.map do |data_name|
        data = inlist.inlist_data.select { |datum| datum.name == data_name }
        if data.empty?
          nil
        else
          data.first.val
        end
      end
    end
  end

  def get_data(*data_names)
    inlist_data.load unless inlist_data.loaded?
    if data_names.length == 1
      data = inlist_data.select { |datum| datum.name == data_names[0] }
      return nil if data.empty?
      data.first.val
    else
      data_names.map do |data_name|
        data = inlist_data.select { |datum| datum.name == data_name }
        if data.empty?
          nil
        else
          data.first.val
        end
      end
    end
  end



  def set_tcc
    # do absolutely nothing if this is already set
    return test_case_commit if test_case_commit

    candidate = TestCaseCommit.find_by(
      commit: commit, test_case: test_case
    )
    if candidate
      # found it!
      self.test_case_commit = candidate
    else
      # doesn't exist, so make a new one
      # this one doesn't have status and other values set; this should
      # happen when `update_tcv_or_tcc` is called
      # 
      # frankly, this should never happen, as test case commits should be
      # created after each push event
      self.test_case_commit = TestCaseCommit.create!(
        commit_id: commit.id,
        test_case_id: test_case.id
      )
    end
  end

  def update_tcc
    # make sure we have a test_case_commit
    set_tcc unless self.test_case_commit_id

    # tell the test case commit to update itself
    test_case_commit.update_and_save_scalars
  end

  # overridden to get user names, computer names, and other details
  def as_json(options)
    {
      test_case: test_case.name,
      commit: commit.to_json,
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
      mem_rn: rn_mem_GB,
      mem_re: re_mem_GB,
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
end
