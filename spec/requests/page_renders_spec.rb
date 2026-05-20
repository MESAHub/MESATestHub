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
    # position must be non-nil; branch.nearby_test_case_commits derives a
    # window from it.
    BranchMembership.create!(branch: branch, commit: c, position: 1)
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

  describe 'GET /:branch/commits/:sha' do
    it 'renders successfully' do
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
end
