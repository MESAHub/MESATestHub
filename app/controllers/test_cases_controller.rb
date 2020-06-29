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
    if params[:history_type] == 'show_instances' #|| !params[:show_summaries]
      @test_instances = @test_case.find_instances(params.permit(:computers,
        :start_date, :end_date, :sort_query, :sort_order, :page))
      @show_instances = true
      @show_summaries = false

      # params for table column links
    else
      @show_instances = false
      @show_summaries = true

      @test_case_commits = @test_case.find_test_case_commits(params.permit(
        :status, :start_date, :end_date, :sort_query, :sort_order, :page))

      # if order is set to ascending, switch it. Otherwise pick default
      # value of descending
      status_order = if (params[:sort_order] == 'desc') && params[:sort_query] == 'status'
                       :asc
                     else
                       :desc
                     end
      @status_params = {sort_query: :status, sort_order: status_order}
      date_order = if (params[:sort_order] == 'desc') && params[:sort_query] == 'created_at'
                       :asc
                   else
                       :desc
                   end
      @date_params = {sort_query: :created_at, sort_order: date_order}
    end


    # names of default columns in the table of instances, can be toggled on
    # and off
    @default_columns = {
      'status' => true,
      'computer' => true,
      'date' => false,
      'runtime' => true,
      'ram' => false,
      'checksum' => true,
      'threads' => false,
      'spec' => false,
      'steps' => true,
      'retries' => true,
      'redos' => false,
      'solver_iterations' => false,
      'solver_calls_made' => false,
      'solver_calls_failed' => false,
      'log_rel_run_E_err' => false
    }

    @specific_columns = []
  end

  private
  # Use callbacks to share common setup or constraints between actions.
  def set_test_case
    @test_case = TestCase.includes(:test_case_commits).find_by(name: params[:test_case], module: params[:module])
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
end
