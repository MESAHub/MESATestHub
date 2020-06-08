class TestCaseCommitsController < ApplicationController
  before_action :set_test_case_commit, only: %i[show]

  def show
    # big daddy query, hopefully optimized
    @mesa_commits = @test_case.commits.order(commit_time: :desc).uniq
    @selected = @commit
    @test_case_commits = @commit.test_case_commits.includes(:test_case).to_a
    @test_case_commits.sort_by! { |tcc| [-tcc.status, tcc.test_case.name] }
    @tc_options = @test_case_commits.map do |tcc|
      [tcc.test_case.name, tcc.test_case.module]
    end

    # all test instances, sorted by upload date
    @instance_limit = 25
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

  end

  def show_test_case_commit
    redirect_to test_case_commit_path(
      sha: params[:sha], test_case: params[:test_case], module: params[:module]
    )
  end

  private
  # Use callbacks to share common setup or constraints between actions.

  def set_test_case_commit
    @commit = parse_sha
    @test_case = TestCase.find_by(name: params[:test_case], module: params[:module])
    @test_case_commit = TestCaseCommit.find_by(
      commit: @commit, test_case: @test_case
    )
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
