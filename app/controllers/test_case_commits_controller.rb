class TestCaseCommitsController < ApplicationController
  before_action :set_test_case_commit, only: %i[show]

  def show
    # set up branch/commit selector
    @selected_branch = Branch.named(params[:branch])
    @other_branches = @commit.branches.reject do |branch|
      branch == @selected_branch
    end
    @branches = [@selected_branch, @other_branches].flatten

    # populating test case commit dropdown menu. In the future, might want to
    # move this to happen via asynchronous request from javascript to speed up
    # rendering (no need to wait for github api call in determining nearby
    # commits)

    # get nearby commits for populating dropdown menu
    # @nearby_commits = @selected_branch.nearby_commits(@commit)
    @nearby_tccs = @selected_branch.nearby_test_case_commits(@test_case_commit)

    @next_tcc, @previous_tcc = nil, nil
    loc = @nearby_tccs.pluck(:id).index(@test_case_commit.id)

    # we've reversed nearby commits, so the "next" one is later in time, and
    # thus EARLIER in the array. Clunky, but I think it works in practice
    @next_tcc = @nearby_tccs[loc - 1] if loc.positive?
    if loc < @nearby_tccs.length - 1
      @previous_tcc = @nearby_tccs[loc + 1]
    end


    # used for shading commit selector options according to passage status of
    # THIS test
    @commit_classes = Hash.new('list-group-item-info')
    @btn_classes = Hash.new('btn-info')
    @nearby_tccs.each do |tcc|
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
      'log_rel_run_E_err' => false,
      'model_number' => false,
      'star_age' => false,
      'num_retries' => true
    }

    @specific_columns = {}
    data_names = @test_case_commit.inlist_data.pluck(:name).uniq

    # only show special data by default if we only have one or two. Otherwise
    # rely on users to click the checkboxes they want to use
    data_names.each do |data_name|
      @specific_columns[data_name] = data_names.length < 3
    end

    # gather all inlists from the instances already in memory
    # default scope of InstanceInlist should ensure they are read off in the
    # proper order. Not sure how this would work if one instance skipped an
    # inlist. Hopefully that doesn't happen.
    @raw_inlists = []
    @inlists = []
    @test_case_commit.test_instances.each do |ti|
      if ti.instance_inlists.count > @inlists.count
        @inlists = ti.instance_inlists.map do |inlist|
          inlist.inlist.sub(/^inlist_/, '').sub(/_header$/, '')
        end
        # puts "setting raw_inlists"
        @raw_inlists = ti.instance_inlists.map(&:inlist)
        # puts "raw inlists now set to"
        # @raw_inlists.each { |inl| puts "- #{inl}"}
      end
    end

    # need to gather data for each instance inlist. Should be simple, but a few
    # pieces of data are tricky, so doing this here rather than making the view
    # horrendous
    #
    # Create a hash with inlist names as keys and lists of data hashes as values
    # each element in the values will encode all of the table data needed for
    # one computer's submission of that inlist
    @inlist_data = Hash.new([])
    @test_case_commit.test_instances.each do |ti|
      @inlists.zip(@raw_inlists).each do |inlist_short, inlist_full|
        # puts "Gathering data for computer #{ti.computer} and inlist #{inlist_full}"
        inlist = ti.instance_inlists.select do |inl|
          inl.inlist == inlist_full
        end
        next if inlist.empty?
        
        inlist = inlist.first
        data_hash = {}

        # inlist "passed" if the next one exists OR this is the last one and
        # the overall test passed
        data_hash[:passed] = false
        if inlist_short == @inlists.last
          data_hash[:passed] = ti.passed
        elsif ti.instance_inlists.pluck(:order).include? inlist.order + 1
          data_hash[:passed] = true
        end

        data_hash[:computer] = ti.computer
        data_hash[:runtime] = inlist.runtime_minutes
        data_hash[:threads] = ti.omp_num_threads
        data_hash[:spec] = ti.computer_specification
        data_hash[:fpe_checks] = ti.fpe_checks
        data_hash[:run_optional] = ti.run_optional
        data_hash[:model_number] = inlist.model_number || -1
        data_hash[:star_age] = inlist.star_age || -1
        data_hash[:num_retries] = inlist.num_retries || -1

        @specific_columns.each do |col_name|
          data_hash[col_name] = if ti.get_data(col_name)
                                  format('%0.3g', ti.get_data(col_name))
                                else
                                  ''
                                end
        end

        # all other useful data just comes straight from the inlist object
        data_hash = inlist.serializable_hash.to_hash.merge(data_hash)
        # puts "keys are"
        # data_hash.keys.each { |key| puts "- #{key}" }

        # puts "created at is #{data_hash[:created_at]}"
        # puts "runtime is #{data_hash[:runtime_minutes]}"
        # puts "runtime should be #{inlist.serializable_hash['runtime_minutes']}"

        @inlist_data[inlist_short] = [@inlist_data[inlist_short], data_hash].flatten
      end
    end

    # puts "keys to inlist_data, and the length of their each's arrays"
    # @inlist_data.each do |key, val|
      # puts "#{key}: #{val.length}"
    # end

  end

  def show_test_case_commit
    redirect_to test_case_commit_path(
      sha: params[:sha], test_case: params[:test_case], module: params[:module]
    )
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_test_case_commit
    @commit = parse_sha(includes: { test_case_commits: :test_case })
    @test_case = TestCase.find_by(name: params[:test_case], module: params[:module])
    @test_case_commit = TestCaseCommit.includes(
      test_instances: { instance_inlists: :inlist_data, computer: :user }
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
