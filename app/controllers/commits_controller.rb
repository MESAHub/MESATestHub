class CommitsController < ApplicationController
  skip_before_action :authorize_user, only: :show, if: :root_page?
  before_action :set_commit, only: :show
  layout "modern", only: [:index]

  def show
    @test_case_commits = [@problem_tccs, @skimpy_tccs].flatten.sort_by(&:test_case)

    # populate branch/commit selection menus
    # get all branches that contain this commit, this will be first dropdown
    @selected_branch = Branch.includes(:head).named(CGI.unescape(params[:branch]))
    unless @selected_branch
      # show commit on main if it is there (most likely the old branch was merged into main)
      @selected_branch = Branch.main if @commit.branches.include?(Branch.main)
      
      # didn't find the commit in main? Then just use the first branch we can find.
      @selected_branch ||= @commit.branches.first
      
      # redirect to working path if the specified branch is wrong
      redirect_to(commit_path(sha: @commit.short_sha, branch: @selected_branch.name), alert: "Branch <span class='text-monospace'>#{CGI.unescape(params[:branch])}</span> does not exist. Found commit in <span class='text-monospace'>#{@selected_branch}</span>.") and return
    end
    @other_branches = @commit.branches.reject do |branch|
      branch == @selected_branch
    end.sort_by { |c| c.updated_at }
    @branches = [@selected_branch, @other_branches].flatten

    # branches that do not contain this commit. Want these for easy navigation,
    # but they will redirect to the head commits of their respective branches
    # — so filter out any branches with no head_id (they'd crash the view
    # when it asks for branch.head.short_sha).
    @branches_off_recent = Branch.recent.where.not(id: @branches.map(&:id))
                                        .where.not(head_id: nil)
    @branches_off_older  = Branch.older.where.not(id: @branches.map(&:id))
                                       .where.not(head_id: nil)

    # Get array of commits made in the same branch around the same time of this
    # commit. For now, get no more than five commits, ideally centered
    # at current commit in time in the branch. That is, if this is the head
    # commit, get ten last commits. If this is the first commit of a branch,
    # get the next ten. If it is in the middle, get five on either side.

    @next_commit, @previous_commit = nil, nil

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
      if tcc.checksum_count > 1
        unique_checksums = tcc.unique_checksums
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

      if tcc.failed_count.positive?
        @failing_instances[tcc] = tcc.test_instances.reject(&:passed)
        @failure_types[tcc] = {}
        # create hash that has failure types as keys and arrays of computers,
        # sorted by name, as values
        @failing_instances[tcc].pluck(:failure_type).uniq.each do |failure_type|
          @failure_types[tcc][failure_type] = @failing_instances[tcc].select do |ti|
            ti.failure_type == failure_type
          end.map do |ti| 
            { 
              computer: ti.computer.name,
              run_optional: ti.run_optional,
              fpe_checks: ti.fpe_checks,
              resolution_factor: ti.resolution_factor
            }
          end.uniq.sort_by do |failure_config|
            [failure_config[:run_optional] ? 0 : 1,
             failure_config[:fpe_checks] ? 0 : 1,
             failure_config[:computer]]
          end
        end
      end
      @counts[tcc] = {}
      @counts[tcc][:computers] = tcc.computer_count
      @counts[tcc][:passes] = tcc.passed_count
      @counts[tcc][:failures] = tcc.failed_count
      @counts[tcc][:checksums] = tcc.checksum_count
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
    @branches = Branch.includes(:head).order(:name)
    @branch_names = @branches.pluck(:name)
    @branch = if @branch_names.include? CGI.unescape(params[:branch])
                @branches[@branch_names.index(CGI.unescape(params[:branch]))]
              else
                redirect_to(commits_path(branch: 'main'), alert: "Branch <span class='text-monospace'>#{CGI.unescape(params[:branch])}</span> does not exist; showing commits on <span class='text-monospace'>main</span>.") and return
              end

    # Cursor pagination by commit_time. Two URL params drive it:
    #
    #   ?before=X   page of newest 25 commits with commit_time < X.
    #               Map initializes at the "newest" view (commits
    #               0..12 of the 25 visible on the left).
    #   ?after=Y    page of oldest 25 commits with commit_time > Y,
    #               displayed newest-first. Map initializes at the
    #               "oldest" view (commits 12..24) — i.e., the
    #               bridge between this page and the older one the
    #               user just panned from.
    #
    # Bare dates parse to end-of-day for `before` (so the picked day
    # is included) and beginning-of-day for `after` (so the picked
    # day is also included). Either form is bookmarkable.
    #
    # The headline + date chip always show "on or before <newest
    # visible>" regardless of which param produced the page, so the
    # `?after=` form is a navigation detail rather than a different
    # mental model for the user.
    @page_size = (params[:per_page] || 25).to_i.clamp(5, 200)

    if params[:after].present?
      @after_time = parse_after_param(params[:after])
      rows = @branch.ordered_commits
                    .where('commits.commit_time > ?', @after_time)
                    .reorder('commits.commit_time ASC')
                    .limit(@page_size + 1)
                    .includes(:submissions,
                              test_case_commits: { test_instances: [] })
                    .to_a
      @has_more_newer = rows.size > @page_size
      rows.pop if @has_more_newer
      @commits = rows.reverse
      @map_initial_view = :oldest
      @at_head_of_history = false
    else
      @before_time_param = parse_before_param(params[:before])
      @before_explicit = params[:before].present?
      rows = @branch.ordered_commits
                    .where('commits.commit_time < ?', @before_time_param)
                    .limit(@page_size + 1)
                    .includes(:submissions,
                              test_case_commits: { test_instances: [] })
                    .to_a
      @has_more_older_via_main_fetch = rows.size > @page_size
      rows.pop if @has_more_older_via_main_fetch
      @commits = rows
      @map_initial_view = :newest
      @at_head_of_history = !@before_explicit
    end

    # Whether the opposite-direction page exists. The main fetch
    # already told us about one direction (via the +1 trick); for
    # the other we run a cheap EXISTS against the same recursive
    # CTE. On a multi-thousand-commit branch this stays sub-ms.
    if @commits.any?
      newest_visible_time = @commits.first.commit_time
      oldest_visible_time = @commits.last.commit_time
      @has_more_older =
        if defined?(@has_more_older_via_main_fetch)
          @has_more_older_via_main_fetch
        else
          Commit.from("(#{@branch.reachable_commits_sql}) AS commits")
                .where('commits.commit_time < ?', oldest_visible_time)
                .exists?
        end
      @has_more_newer ||=
        if @at_head_of_history
          false
        else
          Commit.from("(#{@branch.reachable_commits_sql}) AS commits")
                .where('commits.commit_time > ?', newest_visible_time)
                .exists?
        end
    else
      @has_more_older = false
      @has_more_newer = false
    end

    # Effective display cursor — what the headline + date chip read.
    @before_time = @commits.first&.commit_time || @before_time_param || Time.zone.now

    @older_href =
      if @has_more_older
        commits_path(branch: @branch.name, before: (@commits.last.commit_time - 1.second).iso8601)
      end
    @newer_href =
      if @has_more_newer
        commits_path(branch: @branch.name, after: @commits.first.commit_time.iso8601)
      end

    @max_num = @branch.reachable_commit_count

    # Per-commit aggregated state — feeds the status dot, pills, flag
    # chips, and the subway map. The CommitState concern memoizes its
    # queries on each Commit instance, so calling these helpers across
    # views in the same request stays cheap.
    @commit_states = @commits.each_with_object({}) do |commit, h|
      h[commit.id] = commit.commit_state
    end

    @last_activity_at = @commits.first&.commit_time
  end

  # API call to allow asynchronous loading of nearby commits
  def nearby_commits
    branch = Branch.includes(:head).named(CGI.unescape(params[:branch]))
    this_commit = Commit.parse_sha(params[:sha])
    commits = branch.nearby_commits(this_commit)

    res = {}
    unless commits.nil? || commits.empty?
      res[:commits] = commits.map do |commit|
        {
          short_sha: commit.short_sha,
          message_first_line: commit.message_first_line(40),
          run_optional: commit.run_optional?,
          fpe_checks: commit.fpe_checks?,
          fine_resolution: commit.fine_resolution?,
          author: commit.author,
          commit_time: format_time(commit.commit_time),
          message_rest: commit.message_rest(40),
          status: commit.status,
          url: commit_url(branch: branch.name, sha: commit.short_sha)
        }
      end
    end

    respond_to do |format|
      format.json do
        render json: res.to_json
      end
    end
  end

  private

  # Parse the `before=` URL parameter for cursor pagination.
  #
  #   blank        → "now" (latest commits)
  #   "2026-03-05" → end of Mar 5 in the request's time zone so the
  #                  whole day is included
  #   ISO 8601 ts  → exact moment, as produced by the Older/Newer link
  #                  builders
  #
  # Bad input falls back to "now" rather than 422-ing — this is a
  # navigation parameter, not data.
  def parse_before_param(value)
    return Time.zone.now if value.blank?

    if value.to_s.match?(/[T:]/)
      Time.zone.parse(value.to_s) || Time.zone.now
    else
      Date.parse(value.to_s).in_time_zone.end_of_day
    end
  rescue ArgumentError, Date::Error
    Time.zone.now
  end

  # Sister parser for the `after=` URL parameter — the lower-bound
  # cursor used when navigating from a page to its newer neighbor.
  # Bare dates parse to beginning-of-day so the picked day itself is
  # included in the result set.
  def parse_after_param(value)
    return nil if value.blank?

    if value.to_s.match?(/[T:]/)
      Time.zone.parse(value.to_s)
    else
      Date.parse(value.to_s).in_time_zone.beginning_of_day
    end
  rescue ArgumentError, Date::Error
    nil
  end

  def root_page?
    params[:sha] == 'head' && params[:branch] == 'main'
  end

  def set_commit
    # @commit = parse_sha(includes: {test_case_commits: [:test_case, {test_instances: [:computer, instance_inlists: :inlist_data]}]})
    @commit = parse_sha(includes: :branches)

    # bail to commits index if the commit doesn't exist
    unless @commit
      redirect_to(commits_path(branch: 'main'), alert: "Could not locate commit <span class='text-monospace'>#{params[:sha]}</span> in any branch. Showing commits in <span class='text-monospace'>main</span>.") and return
    end

    # avoid polling db for tons of instances and instance data if they passed
    # or haven't been tested. Results in an extra call, but avoiding a dragnet
    # of instance data is worth it (I think)
    #
    # First get test cases that are failing, have multiple checksums, or are
    # mixed, for which we will need more information
    @problem_tccs = @commit.test_case_commits.includes(
      :test_case,
      { test_instances: [:computer, { instance_inlists: :inlist_data }] }
    ).where.not(status: -1..0).to_a
    @skimpy_tccs = @commit.test_case_commits.includes(:test_case)
                          .where(status: -1..0).to_a
  end
end
