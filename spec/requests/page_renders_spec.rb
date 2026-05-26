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

    context 'branch-mismatch redirect' do
      let(:feature_branch) { create(:branch, name: 'feature/x') }
      let(:other_commit) do
        c = create(:commit)
        BranchMembership.create!(branch: feature_branch, commit: c)
        feature_branch.update!(head: c)
        c
      end

      it 'redirects to a containing branch when the URL branch does not contain the commit' do
        get "/main/commits/#{other_commit.short_sha}"

        expect(response).to redirect_to("/feature%2Fx/commits/#{other_commit.short_sha}")
        expect(flash[:warning]).to include("Branch 'main' doesn't contain")
        expect(flash[:warning]).to include(other_commit.short_sha)
        expect(flash[:warning]).to include("'feature/x'")
      end

      it 'redirects to main when main contains the commit and the URL branch does not exist' do
        get "/no-such-branch/commits/#{commit.short_sha}"

        expect(response).to redirect_to("/main/commits/#{commit.short_sha}")
        expect(flash[:warning]).to include("Branch 'no-such-branch' doesn't exist")
        expect(flash[:warning]).to include("'main'")
      end

      it 'lists other containing branches in the flash when there are multiple' do
        also = create(:branch, name: 'jenkins')
        BranchMembership.create!(branch: also, commit: commit)

        get "/no-such-branch/commits/#{commit.short_sha}"

        expect(flash[:warning]).to include("Also on: jenkins")
      end

      it 'picks the most-recent-head branch when main is not a candidate' do
        old_branch = create(:branch, name: 'a-old')
        new_branch = create(:branch, name: 'z-new')
        old_head = create(:commit, commit_time: 10.days.ago)
        new_head = create(:commit, commit_time: 1.day.ago)
        BranchMembership.create!(branch: old_branch, commit: old_head)
        BranchMembership.create!(branch: new_branch, commit: new_head)
        old_branch.update!(head: old_head)
        new_branch.update!(head: new_head)

        orphan = create(:commit)
        BranchMembership.create!(branch: old_branch, commit: orphan)
        BranchMembership.create!(branch: new_branch, commit: orphan)

        get "/main/commits/#{orphan.short_sha}"

        # main doesn't contain orphan; of the two that do, z-new's head is
        # more recent than a-old's, so it wins despite alphabetical order.
        expect(response).to redirect_to("/z-new/commits/#{orphan.short_sha}")
      end
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

    it 'redirects to a containing branch when the URL branch does not contain the commit' do
      feature_branch = create(:branch, name: 'feature/x')
      other_commit = create(:commit)
      BranchMembership.create!(branch: feature_branch, commit: other_commit)
      feature_branch.update!(head: other_commit)
      TestCaseCommit.create!(test_case: test_case, commit: other_commit)

      get "/main/commits/#{other_commit.short_sha}/test_cases/#{test_case.module}/#{test_case.name}"

      expect(response).to redirect_to(
        "/feature%2Fx/commits/#{other_commit.short_sha}/test_cases/#{test_case.module}/#{test_case.name}"
      )
      expect(flash[:warning]).to include("Branch 'main' doesn't contain")
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
      # Modern layout fingerprints — the skip-link, the Tailwind
      # stylesheet, the theme controller wiring, and the page
      # body itself.
      expect(response.body).to include('Skip to main content')
      expect(response.body).to include('Page not found')
      expect(response.body).to include('tailwind')
      expect(response.body).to match(/data-controller=['"]theme['"]/)
    end
  end
end
