class TestCasesController < ApplicationController
  layout "modern", only: :show

  before_action :set_test_case, only: :show

  def show
    @selected_branch = Branch.named(params[:branch]) || Branch.main
    return render_404("Branch '#{params[:branch]}' not found") unless @selected_branch

    # Pickers in the headline. The test picker spans every test case
    # in the catalog so the user can jump anywhere. The branch picker
    # uses the same recent/older split as the commits index.
    @test_cases      = TestCase.ordered_cases.to_a
    @recent_branches = Branch.recent
    @older_branches  = Branch.older

    @status_summary = @test_case.status_summary_for(@selected_branch)

    @active_tab = parse_tab(params[:tab])

    # Shared time window for all tabs that show per-commit data
    # (History today, Trend next). Anchor + size live in the URL so
    # deep links round-trip; the toolbar's pan arrows just rewrite
    # ?anchor= to a new SHA.
    @window_size    = parse_window_size(params[:window])
    @anchor_commit  = resolve_anchor_commit(@selected_branch, params)
    @window         = @test_case.commit_window(@selected_branch,
                                               anchor_commit: @anchor_commit,
                                               size: @window_size)

    # Trend payload — built only when the Trend tab is active. The
    # query cost (per-instance iteration plus inlist_data scan) is
    # avoided when the user is on History or Submissions. The
    # payload uses the same window entries so all tabs stay in
    # lockstep with the toolbar.
    @trend_payload = if @active_tab == :trend
                       @test_case.trend_payload(@selected_branch, @window[:entries])
                     end
  end

  private

  def set_test_case
    @test_case = TestCase.find_by(name: params[:test_case],
                                  module: params[:module])
    return render_404("Test case '#{params[:module]}/#{params[:test_case]}' not found") unless @test_case
  end

  def parse_tab(raw)
    sym = raw.to_s.to_sym
    %i[history trend submissions].include?(sym) ? sym : :history
  end

  def parse_window_size(raw)
    n = raw.to_i
    TestCase::WINDOW_SIZES.include?(n) ? n : TestCase::DEFAULT_WINDOW_SIZE
  end

  # Resolve the URL params (`?center=<sha>` or `?center_date=YYYY-MM-DD`)
  # to a Commit on `branch`. Precedence: explicit SHA > date snap >
  # branch HEAD. The date snap finds the most-recent commit at or
  # before the given date so "jump to last March" works even if no
  # commit landed on the exact date.
  #
  # NOTE on naming: this param is `center`, not `anchor`, because
  # Rails' `url_for` treats `:anchor` as the URL fragment (#...) — a
  # `test_case_path(anchor: x)` call writes `…#x`, not `…?anchor=x`,
  # which silently breaks GET round-trips. Use `center` everywhere
  # in this controller and its views.
  #
  # Returns nil if a SHA was supplied but doesn't resolve — the view
  # then renders an empty window with a "couldn't find that commit"
  # hint rather than silently falling back to HEAD (which would mask
  # a typo).
  def resolve_anchor_commit(branch, params)
    sha = params[:center].to_s.strip
    if sha.present? && sha.downcase != "head"
      return Commit.parse_sha(sha, branch: branch.name)
    end

    if (date_str = params[:center_date].to_s.strip).present?
      begin
        date = Date.parse(date_str)
        anchor = branch.ordered_commits
                       .where("commits.commit_time <= ?", date.end_of_day)
                       .first
        return anchor if anchor
      rescue ArgumentError
        # fall through to HEAD on a malformed date
      end
    end

    branch.head
  end
end
