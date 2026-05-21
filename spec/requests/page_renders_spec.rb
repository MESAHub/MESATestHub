require 'rails_helper'

# Smoke tests for the three highest-traffic pages. They don't assert
# fine-grained content — just that an authenticated user hitting these
# routes with realistic params gets a 2xx back. Catches regressions like
# missing partials, undefined helpers, broken view code.
RSpec.describe 'Page renders', type: :request do
  let(:user) { create(:user, password: 'pw-12345678', password_confirmation: 'pw-12345678') }
  let(:branch) { create(:branch, name: 'main') }
  let(:commit) do
    c = create(:commit)
    # Memberships supply the "is this commit in this branch?" cache used
    # by nearby_commits/nearby_test_case_commits; head_id drives the
    # CTE for ordered_commits. Both are needed for the smoke pages.
    BranchMembership.create!(branch: branch, commit: c)
    branch.update!(head: c)
    c
  end
  let(:test_case) { create(:test_case) }
  let!(:test_case_commit) do
    TestCaseCommit.create!(test_case: test_case, commit: commit)
  end

  before do
    post '/sessions', params: { email: user.email, password: 'pw-12345678' }
  end

  describe 'GET /:branch/commits/:sha/build_log/:computer' do
    let(:computer) { create(:computer, name: 'rusty', user: user) }
    let!(:submission) { create(:submission, commit: commit, computer: computer) }

    it 'returns 404 when the computer has no submissions for this commit' do
      get "/main/commits/#{commit.short_sha}/build_log/never-submitted"

      expect(response).to have_http_status(:not_found)
      expect(response.body).to include('no submissions')
    end

    it 'returns 404 when the commit does not exist' do
      get "/main/commits/deadbeef/build_log/rusty"

      expect(response).to have_http_status(:not_found)
      expect(response.body).to include('Commit not found')
    end
  end

  describe 'GET /:branch/commits/:sha' do
    it 'renders successfully' do
      get "/main/commits/#{commit.short_sha}"

      expect(response).to have_http_status(:ok)
    end

    it 'does not crash when another recent branch has nil head_id' do
      # The "Other Active Branches" dropdown renders branch.head.short_sha;
      # a branch with no head (left in that state by an interrupted sync
      # or an older creation path that didn't set head_id) used to crash
      # the entire show page.
      create(:branch, name: 'half-synced', head_id: nil)

      get "/main/commits/#{commit.short_sha}"

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'GET /:branch/commits' do
    it 'renders the commits index' do
      get '/main/commits'

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'GET /:branch/test_cases/:module/:test_case' do
    it 'renders the test-case-across-commits view' do
      get "/main/test_cases/#{test_case.module}/#{test_case.name}"

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'GET /:branch/commits/:sha/test_cases/:module/:test_case' do
    it 'renders the test case commit detail view' do
      get "/main/commits/#{commit.short_sha}/test_cases/#{test_case.module}/#{test_case.name}"

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'GET / (root → commit head)' do
    it 'renders when there is a main branch with a head commit' do
      # The root route is commits#show with sha=head, branch=main. set_commit
      # resolves these via Commit.parse_sha which looks up the head of main.
      get '/'

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'render_404 (modern layout)' do
    # Confirms the Tailwind/Hotwire layout boots cleanly during Phase 4.
    # test_case_commits#show falls into render_404 when the SHA misses,
    # which renders errors/not_found inside layouts/modern.html.haml.
    it 'renders the modern layout for a missing test_case_commit' do
      get "/main/commits/deadbeef0000/test_cases/#{test_case.module}/#{test_case.name}"

      expect(response).to have_http_status(:not_found)
      expect(response.body).to include('mesa-modern')
      expect(response.body).to include('Page not found')
      expect(response.body).to include('tailwind')
      expect(response.body).to match(/data-controller=['"]theme['"]/)
    end
  end
end
