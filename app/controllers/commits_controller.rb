class CommitsController < ApplicationController
  before_action :set_commit, only: :show

  def show
    @test_case_commits = @commit.test_case_commits.includes(
      :test_case, test_instances: [:computer, instance_inlists: :inlist_data])
    @test_case_commits = @test_case_commits.to_a.sort_by do |tcc|
      tcc.test_case.name
    end

    # populate branch/commit selection menus
    # get all branches that contain this commit, this will be first dropdown
    @selected_branch = Branch.named(params[:branch])
    @other_branches = @commit.branches.reject do |branch|
      branch == @selected_branch
    end
    @branches = [@selected_branch, @other_branches].flatten

    # Get array of commits made in the same branch around the same time of this
    # commit. For now, get no more than seven commits, ideally centered
    # at current commit in time in the branch. That is, if this is the head
    # commit, get ten last commits. If this is the first commit of a branch,
    # get the next ten. If it is in the middle, get five on either side.
    commit_shas = Commit.api_commits(
      sha: @selected_branch.head.sha,
      before: 10.days.after(@commit.commit_time),
      after: 10.days.before(@commit.commit_time)
    ).map { |c| c[:sha] }
    @nearby_commits = @selected_branch.commits.where(sha: commit_shas).to_a
      .sort! { |a, b| commit_shas.index(a.sha) <=> commit_shas.index(b.sha) }      

    @next_commit, @previous_commit = nil, nil

    loc = @nearby_commits.pluck(:id).index(@commit.id)
    start_i = [0, loc - 2].max
    stop_i = [@nearby_commits.length - 1, loc + 2].min
    @nearby_commits = @nearby_commits[start_i..stop_i]
    loc = @nearby_commits.pluck(:id).index(@commit.id)

    # we've reversed nearby commits, so the "next" one is later in time, and 
    # thus EARLIER in the array. Clunky, but I think it works in practice
    if loc > 0
    @next_commit = @nearby_commits[loc - 1]
    end
    if loc < @nearby_commits.length - 1
      @previous_commit = @nearby_commits[loc + 1]
    end


    @others = @test_case_commits.select { |tcc| !(0..3).include? tcc.status }
    @mixed = @test_case_commits.select { |tcc| tcc.status == 3 }
    @checksums = @test_case_commits.select { |tcc| tcc.status == 2 }
    @failing = @test_case_commits.select { |tcc| tcc.status == 1 }
    @passing = @test_case_commits.select { |tcc| tcc.status == 0 }
    @test_case_commits = [@others, @mixed, @checksums, @failing, @passing].flatten

    @specs = @commit.computer_info
    @statistics = {
      passing: @test_case_commits.select { |tcc| tcc.status.zero? }.count,
      mixed: @test_case_commits.select { |tcc| tcc.status == 3 }.count,
      failing: @test_case_commits.select { |tcc| tcc.status == 1 }.count,
      checksums: @test_case_commits.select { |tcc| tcc.status == 2 }.count,
      other: @test_case_commits.select { |tcc| !(0..3).include? tcc.status }.count
    }

    # giant structure that holds all relevant counts for displaying badges next
    # to test case commits
    @counts = {}
    @failing_instances = {}
    @failure_types = {}
    @checksum_groups = {}
    @test_case_commits.each do |tcc|
      unique_checksums = tcc.test_instances.map { |ti| ti.checksum }.uniq
      unique_checksums.reject! { |checksum| checksum.nil? || checksum.empty? }

      if unique_checksums.count > 1
        @checksum_groups[tcc] = {}
        unique_checksums.each do |checksum|
          # more than one checksum? group computers, sorted by name, as values
          # in a hash accessed by their matching checksums
          @checksum_groups[tcc][checksum] = tcc.test_instances.select do |ti|
            ti.checksum == checksum
          end.map { |ti| ti.computer }.uniq.sort_by { |comp| comp.name.downcase }
          # puts '########################################'
          # puts "just assigned checksum #{checksum}"
          # puts '########################################'
        end
      end

      @failing_instances[tcc] = tcc.test_instances.select { |ti| !ti.passed }
      if @failing_instances[tcc].count.positive?
        @failure_types[tcc] = {}
        # create hash that has failure types as keys and arrays of computers,
        # sorted by name, as values
        @failing_instances[tcc].pluck(:failure_type).uniq.each do |failure_type|
          @failure_types[tcc][failure_type] = @failing_instances[tcc].select do |ti|
            ti.failure_type == failure_type
          end.map { |ti| ti.computer }
        end
      end
      @counts[tcc] = {}
      @counts[tcc][:computers] = tcc.computer_count
      @counts[tcc][:passes] = tcc.test_instances.count { |ti| ti.passed }
      @counts[tcc][:failures] = @failing_instances[tcc].count
      @counts[tcc][:checksums] = tcc.unique_checksums.count
    end

    @commit_status = case @commit.status
                      when 0 then :passing
                      when 1 then :failing
                      when 2 then :checksum
                      when 3 then :mixed
                      when -1 then :other
                      else
                        :untested
                      end

    @status_text = case @commit_status
                   when :passing then 'All tests passing on all computers.'
                   when :mixed
                     'Some tests fail on some computers and pass on others.'
                   when :failing then 'Some tests fail with all computers.'
                   when :checksum then 'Some tests pass with different ' \
                     'checksums on different computers.'
                   when :other then 'At least some test cases not tested.'
                   else
                     'No tests have been run for this commit.'
                   end

    @status_class = case @commit_status
                    when :passing then 'text-success'
                    when :mixed then 'text-warning'
                    when :failing then 'text-danger'
                    when :checksum then 'text-primary'
                    else
                      'text-info'
                    end
    @compilation_text = case @commit.compilation_status
                        when 0 then 'Successfully compiling on ' +
                                    "#{@commit.compile_success_count} " +
                                    'machines.'
                        when 1 then 'Failing to compile on ' \
                                    "#{@commit.compile_fail_count} machines."
                        when 2 then 'Successfully compiling on ' \
                                    "#{@commit.compile_success_count} and " \
                                    'failing to compile on ' \
                                    "#{@commit.compile_fail_count} machines."
                        else
                          'No compilation information'
                        end

    @compilation_class = case @commit.compilation_status
                         when 0 then 'text-success'
                         when 1 then  'text-danger'
                         when 2 then 'text-warning'
                         else
                           'text-info'
                         end

    # set up colored table rows depending on passage status
    @row_classes = {}
    @last_tested = {}
    @test_case_commits.each do |tcc|
      @last_tested[tcc] = tcc.last_tested
      @row_classes[tcc] =
        case tcc.status
        when 0 then 'table-success'
        when 1 then 'table-danger'
        when 2 then 'table-primary'
        when 3 then 'table-warning'
        else
          'table-info'
        end
    end
  end

  def index
    @page_length = 25
    @unmerged_branches = Branch.unmerged
    @merged_branches = Branch.merged
    @branch = params[:branch] ? Branch.named(params[:branch]) : Branch.main
    commit_shas = Commit.api_commits(sha: @branch.head.sha).map { |c| c[:sha] }
    
    @num_commits = commit_shas.length

    # how many pages are there? Which page are we on? Are we REALLY on that page?
    @page = params[:page] || 1
    @page = @page.to_i
    @num_pages = @num_commits / @page_length + 1
    @page = @num_pages if @page > @num_pages
    @start_num = 1 + (@page - 1) * @page_length
    @stop_num = @page_length * @page
    
    subset = commit_shas[@page_length * (@page - 1), @page_length]
    @commits = Commit.includes(:test_case_commits).where(sha: subset).to_a
      .sort! { |a, b| subset.index(a.sha) <=> subset.index(b.sha) }      
    # @commits = @branch.commits.includes(:test_case_commits).order(commit_time: :desc).page(params[:page])
    # Commit.all_in_branch(
    #   branch: @branch,
    #   includes: :test_case_commits,
    #   page: params[:page]
    # )

    @row_classes = {}
    @btn_classes = {}
    @commits.each do |commit|
      @row_classes[commit] = case commit.status
      when 3 then 'list-group-item-warning'
      when 2 then 'list-group-item-primary'
      when 1 then 'list-group-item-danger'
      when 0 then 'list-group-item-success'
      else
        'list-group-item-info'
      end
      @btn_classes[commit] = case commit.status
      when 3 then 'btn-warning'
      when 2 then 'btn-primary'
      when 1 then 'btn-danger'
      when 0 then 'btn-success'
      else
        'btn-info'
      end

    end
  end

  private

  def set_commit
    @commit = parse_sha(includes: {test_case_commits: :test_instances})
  end
end
