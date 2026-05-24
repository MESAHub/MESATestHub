class TestCasesController < ApplicationController
  layout "modern", only: :show

  before_action :set_test_case, only: :show

  HISTORY_PER_PAGE = 25
  PASSAGE_LIMIT    = 60

  def show
    @selected_branch = Branch.named(params[:branch]) || Branch.main
    return render_404("Branch '#{params[:branch]}' not found") unless @selected_branch

    # Pickers in the headline. The test picker spans every test case
    # in the catalog (worst-first by module, then alphabetical) so the
    # user can jump anywhere; the legacy show used the same superset.
    # The branch picker shares the commits-index splitting — recent
    # vs. older — so the dropdown doesn't get crowded by stale
    # feature branches.
    @test_cases     = TestCase.ordered_cases.to_a
    @recent_branches = Branch.recent
    @older_branches  = Branch.older

    @status_summary = @test_case.status_summary_for(@selected_branch)
    @passage_window = @test_case.passage_strip_window(@selected_branch,
                                                       limit: PASSAGE_LIMIT)

    @active_tab = parse_tab(params[:tab])

    # Per-tab payloads are loaded lazily — the History tab is the
    # default and the most common landing, so build its rows here.
    # Trend + Submissions data hangs off later commits in this phase.
    @history_rows = if @active_tab == :history
                      @test_case.history_window(@selected_branch,
                                                page: params[:page],
                                                per:  HISTORY_PER_PAGE)
                    end
  end

  private

  def set_test_case
    @test_case = TestCase.find_by(name: params[:test_case],
                                  module: params[:module])
    return render_404("Test case '#{params[:module]}/#{params[:test_case]}' not found") unless @test_case
  end

  # Tab params come from URL only — bookmarkable deep links to
  # ?tab=trend should still land on Trend after a reload. Anything
  # unrecognized falls back to History.
  def parse_tab(raw)
    sym = raw.to_s.to_sym
    %i[history trend submissions].include?(sym) ? sym : :history
  end
end
