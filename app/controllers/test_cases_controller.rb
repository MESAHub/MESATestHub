class TestCasesController < ApplicationController
  before_action :set_test_case, only: %i[show]

  # GET /test_cases
  # GET /test_cases.json
  def index
    @mesa_versions = Version.order(number: :desc).pluck(:number)
    @selected = params[:version] || 'latest'
    # big daddy query, hopefully optimized
    @version_number = case @selected
                      when 'latest' then @mesa_versions.max
                      else
                        @selected.to_i
                      end
    @version = Version.includes(:test_instances, :test_cases)
                      .find_by(number: @version_number)
                      
    @test_cases = @version.test_cases.order(:name).uniq
    # @test_cases = TestCase.find_by_version(@version_number)
    @header_text = "Test Cases Tested on Version #{@version_number}"
    @specs = @version.computer_specs
    @statistics = @version.statistics
    @version_status =
      if @statistics[:mixed] > 0
        :mixed
      elsif @statistics[:failing] > 0
        if @statistics[:passing] > 0
          :mixed
        else
          :failing
        end
      elsif @statistics[:passing] > 0
        :passing
      else
        :untested
      end

    @status_text = case @version_status
                   when :passing then 'All tests passing on all computers.'
                   when :mixed
                     'Some tests fail on at least some computers.'
                   when :failing then 'All tests fail with all computers.'
                   else
                     'No tests have been run for this version.'
                   end

    @status_class = case @version_status
                    when :passing then 'text-success'
                    when :mixed then 'text-warning'
                    when :failing then 'text-danger'
                    else
                      'text-info'
                    end

    # for populating version select menu
    @mesa_versions.prepend('all')
    @mesa_versions.prepend('latest')

    # set up colored table rows depending on passage status
    @computer_counts = {}
    @last_versions = {}
    @row_classes = {}
    @last_tested = {}
    @test_cases.each do |t|
      if @selected == 'all'
        @last_versions[t] = t.last_version
      else
        @computer_counts[t] = TestCaseVersion.find_by(version: @version, test_case: @test_case).computer_count
      end
      @last_tested[t] = t.last_tested
      @row_classes[t] =
        case @version.status(t)
        when 0 then 'table-success'
        when 1 then 'table-danger'
        else
          'table-warning'
        end
    end
  end

  # GET /test_cases/1
  # GET /test_cases/1.json
  def show
    @test_cases = TestCase.ordered_cases
    @test_cases.load
    @current_test_cases = TestCase.current_cases.to_a
    @unmerged_branches = Commit.unmerged_branches
    @merged_branches = Commit.merged_branches
    @branch = params[:branch] || 'master'

    # status selection menu options
    @status_menu = {
      'Mixed' => {value: 3, klass: "summary"},
      'Multiple Checksums' => {value: 2, klass: "summary"},
      'Failing' => {value: 1, klass: ""},
      'Passing' => {value: 0, klass: ""},
      'Untested' => {value: -1, klass: "summary"}
    }
    @status_options = ""
    @status_menu.keys.sort do |a, b|
      -(@status_menu[a][:value] <=> @status_menu[b][:value])
    end.each do |option|
      data = @status_menu[option]
      selected = data[:value].to_s == params[:status]
      @status_options += "<option value=#{data[:value]}" \
        "#{data[:klass].empty? ? '' : ' class=' + data[:klass]}" \
        "#{selected ? " selected" : ''}"\
        "#{(data[:klass].include?('summary') &&
            ((params[:history_type] == 'show_instances') ||
             (params[:history_type].nil?))) ? " disabled" : ''}>"\
        "#{option}</option>"
    end
    @status_options = "<option value=''>Any Status</option>" + @status_options

    # default start date is 30 days ago
    @end_date = if (test_case_params[:end_date].nil? ||
                    test_case_params[:end_date].empty?)
                  # first use last entered date, then default to today
                  if cookies[:commit_end]
                    Date.parse(cookies[:commit_end])
                  else
                    Date.today
                  end
                else
                  Date.parse(test_case_params[:end_date])
                end
    @start_date = if (test_case_params[:start_date].nil? ||
                      test_case_params[:start_date].empty?)
                    # first use last entered date, then default to one month
                    # ago
                    if cookies[:commit_start]
                      begin
                        Date.parse(cookies[:commit_start])
                      rescue ArgumentError
                        @end_date - 30
                      end
                    else
                      @end_date - 30
                    end
                  else
                    Date.parse(test_case_params[:start_date])
                  end

    # this is the order that each parameter will be sorted by IF YOU CLICK ON
    # THE CORRESPONDING HEADER LINK, it is NOT the current sorting.
    # 
    # So, default is that clicking on the link will sort them in ascending,
    # order, but if it was already sorted according to that value in ascending
    # order, reverse it now
    def get_order(param_name)
      if test_case_params[:sort_order] == 'ASC' &&
         test_case_params[:sort_query] == param_name
        'DESC'
      else
        'ASC'
      end
    end


    if test_case_params[:history_type] == 'show_summaries'
      prepare_summaries
    else
      prepare_instances
    end

    # override default visibilities from cookies
    @default_column_visibility.keys.each do |key|
      klass = "column-#{key}"
      if cookies[klass] == 'checked'
        @default_column_visibility[key] = true
      elsif cookies[klass] == 'unchecked'
        @default_column_visibility[key] = false
      end
    end

    @inlists.each do |inlist|
      @inlist_column_visibility[inlist].keys.each do |key|
        # have to account for periods in classes, which cause problems
        # this is done throughout the view to aid in css selectors
        # (periods indicate classes, so their presence in names wreak havoc)
        klass = "column-#{inlist.sub('.', 'p')}-#{key}"
        if cookies[klass] == 'checked'
          @inlist_column_visibility[inlist][key] = true
        elsif cookies[klass] == 'unchecked'
          @inlist_column_visibility[inlist][key] = false
        end
      end
    end


    # how many columns are shown by default, helps style the table
    @default_width = @default_columns.select do |col|
      @default_column_visibility[col]
    end.count

    # how many columns per inlist are shown by default, helps style the table
    @inlist_width = Hash.new(0)

    @inlists.each do |inlist|
      @inlist_width[inlist] =
        @inlist_column_visibility[inlist].keys.select do |col|
          @inlist_column_visibility[inlist][col]
        end.count
    end

    @orders = {}
    @default_columns.each { |col| @orders[col] = get_order(col) }
    # for styling buttons that take you to test case commits
    @btn_classes = {
      -1 => 'btn-outline-info',
      0 => 'btn-outline-success',
      1 => 'btn-outline-danger',
      2 => 'btn-outline-primary',
      3 => 'btn-outline-warning',
    }

    # all computers for a given branch and range of dates that have any
    # instances of this test case. Used to populate dropdown.
    @computer_options = @test_case.sorted_computers(@branch, @start_date, @end_date)
    
    # make current params available to view so we can merge into them to
    # clean up links
    @current_params = test_case_params
  end

  private
  # Use callbacks to share common setup or constraints between actions.
  def set_test_case
    @test_case = TestCase.includes(:test_case_commits).find_by(name: test_case_params[:test_case], module: test_case_params[:module])
  end

  # prepares various quantities for showing a history of test case commits
  def prepare_summaries
    @show_instances = false
    @show_summaries = true

    @test_case_commits = @test_case.find_test_case_commits(test_case_params.permit(
      :status, :sort_query, :sort_order, :page, :branch), @start_date, @end_date)

    # These "orders" tell the table headings what they should do if they
    # are clicked on. They do NOT mean anything for the ordering of test
    # case commits on the current page, which was already dealt with when
    # the commits were ordered from the database
    # 
    # if order is set to ascending, switch it. Otherwise pick default
    # value of descending
    status_order = if (test_case_params[:sort_order] == 'desc') && test_case_params[:sort_query] == 'status'
                     :asc
                   else
                     :desc
                   end
    @status_params = {sort_query: :status, sort_order: status_order}
    date_order = if test_case_params[:sort_order].nil? ||
                    test_case_params[:sort_order].empty? ||
                    ((test_case_params[:sort_order] == 'desc') &&
                     (test_case_params[:sort_query] == 'created_at'))
                     :asc
                 else
                     :desc
                 end
    @date_params = {sort_query: :created_at, sort_order: date_order}
    # names of default columns in the table of instances, can be toggled on
    # and off
    # NOTE the order of these data columns are hard-coded into the view.
    # Their default visibility, however, is not. So don't mess with the
    # ordering of this array without also changing the view. You CAN, however
    # change the vsibility or titles, which the view will respect.
    @default_columns = %w{commit status date checksum restart_photo} +
                       %w{restart_checksum steps retries redos} +
                       %w{solver_iterations solver_calls_made} +
                       %w{solver_calls_failed}
    @sortable_columns = %w{commit status date}

    @default_column_titles = {
     'commit' => 'Commit',
     'status' => 'Status',
     'date' => 'Commit Date',
     'checksum' => 'Checksum',
     'restart_photo' => 'Re Photo',
     'restart_checksum' => 'Re Checksum',
     'steps' => 'Steps',
     'retries' => 'Retries',
     'redos' => 'Redos',
     'solver_iterations' => 'Iterations',
     'solver_calls_made' => 'Calls Made',
     'solver_calls_failed' => 'Calls Failed'
    }

    # names for columns as they appear in the checkbox form
    @default_column_check_titles = {
      'commit' => 'Commit',
      'status' => 'Status',
      'date' => 'Commit Date',
      'checksum' => 'Checksum',
      'restart_photo' => 'Re Photo',
      'restart_checksum' => 'Re Checksum',
      'steps' => 'Steps',
      'retries' => 'Retries',
      'redos' => 'Redos',
      'solver_iterations' => 'Solver Iterations',
      'solver_calls_made' => 'Solver Calls Made',
      'solver_calls_failed' => 'Solver Calls Failed',
      'log_rel_run_E_err' => 'Log Rel. Run E Err.'
    }

    @default_column_visibility = {
      'commit' => true,
      'status' => true,
      'date' => false,
      'checksum' => false,
      'restart_photo' => false,
      'restart_checksum' => false,
      'steps' => true,
      'retries' => true,
      'redos' => false,
      'solver_iterations' => false,
      'solver_calls_made' => false,
      'solver_calls_failed' => false
    }

    @inlist_column_visibility = Hash.new({
      'steps' => true,
      'retries' => true,
      'redos' => false,
      'solver_iterations' => false,
      'solver_calls_made' => false,
      'solver_calls_failed' => false,
      'log_rel_run_E_err' => false
    })

    @sortable_columns = %w{commit status date}

    # only care about inlists for passing commits
    @inlists = []

    @passing_tccs = @test_case_commits.select { |tcc| tcc.status == 0 }

    @passing_tccs.each do |tcc|
      tcc.test_instances.each do |ti|
        @inlists += ti.instance_inlists.pluck(:inlist)
      end
    end
    # this will have many duplicates
    @inlists.uniq!

    # for consistency, sort alphabetically. Almost certainly isn't in
    # order of how inlists work in the test case
    @inlists.sort!

    @inlist_columns = {}
    @inlists.each do |inlist|
      # all inlists have these columns
      @inlist_columns[inlist] = %w{steps retries redos 
        solver_iterations solver_calls_made solver_calls_failed
        log_rel_run_E_err}

      # now get custom ones
      extras = []

      # only get "this" inlist from each test instance. Need to handle
      # the case where the inlist doesn't exist, though
      @passing_tccs.each do |tcc|
        tcc.test_instances.each do |ti|
          to_access = nil
          ti.instance_inlists.each do |instance_inlist|
            to_access = instance_inlist if (instance_inlist.inlist == inlist)
          end

          # don't have this inlist? just move on
          next if to_access.nil?

          # get names of data for this inlist
          extras += to_access.inlist_data.pluck(:name)
        end
        # same uniqueness/sorting situation as with inlists. Might not be
        # reasonable, but it's consistent
      end
      extras.uniq!
      extras.sort!
      @inlist_columns[inlist] += extras
    end

    # to get scalar data for each commit, look at the first non-skipped
    # instance (only applies to fully-passing, uniform checksum cases)
    # 
    # Note that this doesn't care if there are no checksums, so this may
    # not be EXACTLY a representative test instance.
    @first_instances = {}
    @passing_tccs.each do |tcc|
      @first_instances[tcc] = tcc.test_instances.reject do |ti|
        ti.success_type == 'skip'
      end.first
    end
  end

  def prepare_instances
    @test_instances = @test_case.find_instances(test_case_params.permit(
      :computers, :sort_query, :sort_order, :status, :page, :branch),
      @start_date, @end_date) || []

    @show_instances = true
    @show_summaries = false
    @computer = if @test_instances.empty?
                  nil
                else
                  Computer.includes(:user).find(@test_instances.first.computer_id)
                end

    # all unique inlist names. we will organize columns on a per-inlist
    # basis, so we need these. Order is unfortunately arbitrary
    @inlists = []
    @test_instances.each do |ti|
      @inlists += ti.instance_inlists.pluck(:inlist)
    end
    # this will have many duplicates
    @inlists.uniq!

    # for consistency, sort alphabetically. Almost certainly isn't in
    # order of how inlists work in the test case
    @inlists.sort!

    # get columns specific to each inlist
    @inlist_columns = {}
    @inlists.each do |inlist|
      # all inlists have these columns
      @inlist_columns[inlist] = %w{runtime steps retries redos 
        solver_iterations solver_calls_made solver_calls_failed
        log_rel_run_E_err}

      # now get custom ones
      extras = []

      # only get "this" inlist from each test instance. Need to handle
      # the case where the inlist doesn't exist, though
      @test_instances.each do |ti|
        to_access = ti.instance_inlists.select do |instance_inlist|
          instance_inlist.inlist == inlist
        end
        next if to_access.empty?

        # want the inlist object itself, not an array that contains it
        to_access = to_access.first
        extras += to_access.inlist_data.pluck(:name)
      end
      # same uniqueness/sorting situation as with inlists. Might not be
      extras.uniq!
      extras.sort!
      @inlist_columns[inlist] += extras
    end

    # names of default columns in the table of instances, can be toggled on
    # and off
    @default_columns = %w{commit status date runtime ram checksum } +
                       %w{restart_photo restart_checksum threads spec steps } +
                       %w{retries redos solver_iterations solver_calls_made} +
                       %w{solver_calls_failed}
    @default_column_titles = {
      'commit' => 'Commit',
      'status' => 'Status',
      'date' => 'Date Uploaded',
      'runtime' => 'Runtime [min]',
      'ram' => 'RAM Usage',
      'checksum' => 'Checksum',
      'restart_photo' => 'Re Photo',
      'restart_checksum' => 'Re Checksum',
      'threads' => 'Threads',
      'spec' => 'Computer Specification',
      'steps' => 'Steps',
      'retries' => 'Retries',
      'redos' => 'Redos',
      'solver_iterations' => 'Iterations',
      'solver_calls_made' => 'Calls Made',
      'solver_calls_failed' => 'Calls Failed',
    }

    @specific_columns = @test_instances.map do |ti|
      ti.inlist_data.pluck(:name)
    end.flatten.uniq.sort

    # These "orders" tell the table headings what they should do if they
    # are clicked on. They do NOT mean anything for the ordering of test
    # instances on the current page, which was already dealt with when
    # they were ordered from the database

    @default_column_visibility = {
      'commit' => true,
      'status' => true,
      'date' => false,
      'runtime' => true,
      'ram' => false,
      'checksum' => false,
      'restart_photo' => false,
      'restart_checksum' => false,
      'threads' => false,
      'spec' => false,
      'steps' => true,
      'retries' => true,
      'redos' => false,
      'solver_iterations' => false,
      'solver_calls_made' => false,
      'solver_calls_failed' => false,
    }

    @inlist_column_visibility = Hash.new({
      'runtime' => false,
      'ram' => false,
      'checksum' => false,
      'threads' => false,
      'spec' => false,
      'steps' => true,
      'retries' => true,
      'redos' => false,
      'solver_iterations' => false,
      'solver_calls_made' => false,
      'solver_calls_failed' => false,
    })

    # names for columns as they appear in the checkbox form
    @default_column_check_titles = {
      'commit' => 'Commit',
      'status' => 'Status',
      'date' => 'Date Uploaded',
      'runtime' => 'Runtime',
      'ram' => 'RAM Usage',
      'checksum' => 'Checksum',
      'restart_photo' => 'Re Photo',
      'restart_checksum' => 'Re Checksum',
      'threads' => 'Threads',
      'spec' => 'Computer Spec.',
      'steps' => 'Steps',
      'retries' => 'Retries',
      'redos' => 'Redos',
      'solver_iterations' => 'Solver Iterations',
      'solver_calls_made' => 'Solver Calls Made',
      'solver_calls_failed' => 'Solver Calls Failed',
      'log_rel_run_E_err' => 'Log Rel. Run E Err.'      
    }

    @orders = {}
    @default_columns.each { |col| @orders[col] = get_order(col) }
  end

  # get a bootstrap text class and an appropriate string to convert integer 
  # passing status to useful web output

  def passing_status_and_class(status)
    sts = 'ERROR'
    cls = 'text-info'
    if status == 0
      sts = 'Passing'
      cls = 'text-success'
    elsif status == 1
      sts = 'Failing'
      cls = 'text-danger'
    elsif status == 2
      sts = 'Mismatched checksums'
      cls = 'text-primary'
    elsif status == 3
      sts = 'Mixed'
      cls = 'text-warning'
    else
      sts = 'Not yet run'
      cls = 'text-warning'
    end
    return sts, cls
  end

  def test_case_params
    params.permit(:branch, :module, :test_case, :history_type, :utf8,
                  :computers, :start_date, :end_date, :sort_query, :sort_order,
                  :page, :status)
  end
end
