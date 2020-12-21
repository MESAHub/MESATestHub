class TestCaseCommitsController < ApplicationController
  before_action :set_test_case_commit, only: %i[show]

  def show
    # set up branch/commit selector
    @selected_branch = Branch.named(params[:branch])
    @other_branches = @commit.branches.reject do |branch|
      branch == @selected_branch
    end
    @branches = [@selected_branch, @other_branches].flatten

    @pull_requests = @selected_branch.pull_requests
    @pull_request_tccs = {}
    @pull_requests.each do |pr|
      @pull_request_tccs[pr] = TestCaseCommit.includes(
        test_instances: { instance_inlists: :inlist_data }
      ).find_by(commit: pr, test_case: @test_case)
    end

    # Get array of commits made in the same branch around the same time of this
    # commit. For now, get no more than seven commits, ideally centered
    # at current commit in time in the branch. That is, if this is the head
    # commit, get ten last commits. If this is the first commit of a branch,
    # get the next ten. If it is in the middle, get five on either side.
    @center = @commit.pull_request ? @selected_branch.head : @commit
    commit_shas = Commit.api_commits(
      sha: @selected_branch.head.sha,
      before: 10.days.after(@center.commit_time),
      after: 10.days.before(@center.commit_time)
    ).map { |c| c[:sha] }
    @nearby_commits = @selected_branch.commits.where(sha: commit_shas).to_a
      .sort! { |a, b| commit_shas.index(a.sha) <=> commit_shas.index(b.sha) }     

    @next_commit, @previous_commit = nil, nil

    loc = @nearby_commits.pluck(:id).index(@center.id)
    start_i = [0, loc - 2].max
    stop_i = [@nearby_commits.length - 1, loc + 2].min
    @nearby_commits = @nearby_commits[start_i..stop_i]
    loc = @nearby_commits.pluck(:id).index(@center.id)

    # we've reversed nearby commits, so the "next" one is later in time, and
    # thus EARLIER in the array. Clunky, but I think it works in practice
    if loc > 0
    @next_commit = @nearby_commits[loc - 1]
    end
    if loc < @nearby_commits.length - 1
      @previous_commit = @nearby_commits[loc + 1]
    end

    @nearby_tccs = TestCaseCommit.includes(:commit).where(
      commit: @nearby_commits, test_case: @test_case_commit.test_case
    ).to_a.sort! { |a, b| @nearby_commits.index(a.commit) <=> @nearby_commits.index(b.commit)}

    # used for shading commit selector options according to passage status of
    # THIS test
    @commit_classes = {}
    @btn_classes = {}
    (@nearby_tccs + @pull_request_tccs.values).each do |tcc|
      @commit_classes[tcc.commit] = case tcc.status
      when 0 then 'list-group-item-success'
      when 1 then 'list-group-item-danger'
      when 2 then 'list-group-item-primary'
      when 3 then 'list-group-item-warning'
      else
        'list-group-item-info'
      end
      @btn_classes[tcc.commit] = case tcc.status
      when 0 then 'btn-success'
      when 1 then 'btn-danger'
      when 2 then 'btn-primary'
      when 3 then 'btn-warning'
      else
        'btn-info'
      end

    end

    # other test case commits for this commit
    unsorted = @test_case_commit.commit.test_case_commits.includes(:test_case).each
    @commit_tccs = []

    # set up picky ordering for test case commits: mixed, then checksums, then
    # failing, then passing, then untested. Within each of those, order
    # according to order of modules in TestCase.modules. Within that subset,
    # arrange alphabetically
    [3, 2, 1, 0, -1].each do |status|
      TestCase.modules.each do |mod|
        @commit_tccs += unsorted.select do |tcc|
          (tcc.status == status) && (tcc.test_case.module == mod)
        end.sort { |tcc1, tcc2| tcc1.test_case.name <=> tcc2.test_case.name }
      end
    end
    

    # all test instances, sorted by upload date
    @instance_limit = 100
    @test_instance_classes = {}

    # @test_case_version isn't getting set properly. Need to investigate...

    @test_case_commit.test_instances.each do |instance|
      @test_instance_classes[instance] =
        if instance.passed
          'table-success'
        else
          'table-danger'
        end
    end

    @checksum_count = @test_case_commit.checksum_count

    # text and class for last commit test status
    @commit_status, @commit_class = passing_status_and_class

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

    @specific_columns = {}
    data_names = @test_case_commit.inlist_data.pluck(:name).uniq

    # only show special data by default if we only have one or two. Otherwise
    # rely on users to click the checkboxes they want to use
    data_names.each do |data_name|
      @specific_columns[data_name] = data_names.length < 3
    end
  end

  def show_test_case_commit
    redirect_to test_case_commit_path(
      sha: params[:sha], test_case: params[:test_case], module: params[:module]
    )
  end

  private
  # Use callbacks to share common setup or constraints between actions.

  def set_test_case_commit
    @commit = parse_sha(includes: {test_case_commits: :test_case})
    @test_case = TestCase.find_by(name: params[:test_case], module: params[:module])
    @test_case_commit = TestCaseCommit.includes(
      test_instances: {instance_inlists: :inlist_data}
      ).find_by(commit: @commit, test_case: @test_case)
  end

  # get a bootstrap text class and an appropriate string to convert integer 
  # passing status to useful web output

  def passing_status_and_class
    sts = 'ERROR'
    cls = 'text-danger'
    if @test_case_commit.status == 0
      sts = 'Passing'
      cls = 'text-success'
    elsif @test_case_commit.status == 1
      sts = 'Failing'
      cls = 'text-danger'
    elsif @test_case_commit.status == 2
      sts = 'Checksum mismatch'
      cls = 'text-primary'
    elsif @test_case_commit.status == 3
      sts = 'Mixed'
      cls = 'text-warning'
    elsif @test_case_commit.status == -1
      sts = 'Not yet run'
      cls = 'text-info'
    end
    return sts, cls
  end

end
