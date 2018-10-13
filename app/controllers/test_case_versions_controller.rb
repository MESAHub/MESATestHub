class TestCaseVersionsController < ApplicationController
  before_action :set_test_case_version, only: %i[show]

  def show
    # big daddy query, hopefully optimized
    @mesa_versions = @test_case.versions.order(number: :desc).uniq.pluck(:number)
    @version_number = params[:version]
    @version_number = @version_number.to_i unless @version_number == 'latest'

    # all test instances, sorted by upload date
    @instance_limit = 25
    @test_instance_classes = {}

    # @test_case_version isn't getting set properly. Need to investigate...

    @test_case_version.test_instances.each do |instance|
      @test_instance_classes[instance] =
        if instance.passed
          'table-success'
        else
          'table-danger'
        end
    end

    # text and class for last version test status
    @version_status, @version_class = passing_status_and_class

    # for populating select list
    @mesa_versions.prepend('latest')
  end

  private
  # Use callbacks to share common setup or constraints between actions.

  def set_test_case_version
    @version = if params[:version] == 'latest'
                 Version.order(number: :desc).first
               else
                 Version.find_by(number: params[:version].to_i)
               end
    @test_case = TestCase.find_by(name: params[:test_case])
    @test_case_version = TestCaseVersion.find_by(
      version: @version, test_case: @test_case
    )
  end

  # get a bootstrap text class and an appropriate string to convert integer 
  # passing status to useful web output

  def passing_status_and_class
    sts = 'ERROR'
    cls = 'text-danger'
    if @test_case_version.status == 0
      sts = 'Passing'
      cls = 'text-success'
    elsif @test_case_version.status == 1
      sts = 'Failing'
      cls = 'text-danger'
    elsif @test_case_version.status == 2
      sts = 'Mixed'
      cls = 'text-warning'
    elsif @test_case_version.status == 3
      sts = 'Checksum mismatch'
      cls = 'text-primary'
    elsif @test_case_version.status == -1
      sts = 'Not yet run'
      cls = 'text-info'
    end
    return sts, cls
  end

end
