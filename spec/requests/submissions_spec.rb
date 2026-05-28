require 'rails_helper'

RSpec.describe 'Submissions API', type: :request do
  describe 'POST /submissions/create.json' do
    let(:user) { create(:user, password: 'pw-12345678', password_confirmation: 'pw-12345678') }
    let(:computer) { create(:computer, user: user) }
    let(:branch) { create(:branch, name: 'main') }
    let(:commit) do
      commit = create(:commit)
      BranchMembership.create!(branch: branch, commit: commit)
      commit
    end

    let(:valid_submitter) do
      { email: user.email, password: 'pw-12345678', computer: computer.name }
    end

    let(:valid_commit) do
      { sha: commit.sha, entire: false, empty: true, compiled: true,
        compiler: 'gfortran', compiler_version: '13.2.0',
        sdk_version: '23.7.3', math_backend: 'OpenBLAS' }
    end

    it 'accepts an empty submission with valid credentials' do
      post '/submissions/create.json',
           params: { submitter: valid_submitter, commit: valid_commit },
           as: :json

      expect(response).to have_http_status(:created)
      expect(Submission.count).to eq(1)
      expect(Submission.last.computer).to eq(computer)
      expect(Submission.last.commit).to eq(commit)
      expect(Submission.last.empty).to be true
    end

    it 'renders successfully when the commit has no branch memberships yet' do
      # Regression: _commit.json.jbuilder used to call commit_url with
      # commit.branches[0], which raised on commits not yet attached to a
      # branch — exactly the state of a freshly-ingested commit when the
      # submissions API runs.
      orphan_commit = create(:commit)

      post '/submissions/create.json',
           params: {
             submitter: valid_submitter,
             commit: valid_commit.merge(sha: orphan_commit.sha)
           },
           as: :json

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body['commit']['sha']).to eq(orphan_commit.sha)
      expect(body['commit']).not_to have_key('url')
    end

    it 'rejects submissions with an invalid password' do
      post '/submissions/create.json',
           params: {
             submitter: valid_submitter.merge(password: 'wrong-password'),
             commit: valid_commit
           },
           as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)).to include('error')
      expect(Submission.count).to eq(0)
    end

    it 'rejects submissions for a computer the user does not own' do
      other_user = create(:user)
      other_computer = create(:computer, user: other_user)

      post '/submissions/create.json',
           params: {
             submitter: valid_submitter.merge(computer: other_computer.name),
             commit: valid_commit
           },
           as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(Submission.count).to eq(0)
    end

    it 'rejects submissions for an unknown computer name' do
      post '/submissions/create.json',
           params: {
             submitter: valid_submitter.merge(computer: 'nonexistent-host'),
             commit: valid_commit
           },
           as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(Submission.count).to eq(0)
    end

    it 'rejects submissions for an unknown commit SHA' do
      # api_create fires off a GitHub API call if the commit can't be found
      # locally — stub it to return nil so the spec doesn't hit the network.
      allow(Commit).to receive(:api_create).and_return(nil)

      post '/submissions/create.json',
           params: {
             submitter: valid_submitter,
             commit: valid_commit.merge(sha: 'deadbeef' * 5)
           },
           as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(Submission.count).to eq(0)
    end
  end

  # Phase B of docs/dispatcher-and-claims.md: a submission that
# carries a `claim:` block in the request payload flips the
  # referenced claim to `fulfilled`. Backwards-compatible — old
  # mesa_test versions that don't send the block continue to work.
  describe 'POST /submissions/create.json with a claim:' do
    let(:user) do
      create(:user, password: 'pw-12345678',
                    password_confirmation: 'pw-12345678')
    end
    let(:computer) { create(:computer, user: user) }
    let(:branch)   { create(:branch, name: 'main') }
    let(:commit) do
      c = create(:commit)
      BranchMembership.create!(branch: branch, commit: c)
      c
    end
    let(:valid_submitter) do
      { email: user.email, password: 'pw-12345678', computer: computer.name }
    end
    let(:valid_commit) do
      { sha: commit.sha, entire: false, empty: true, compiled: true,
        compiler: 'gfortran', compiler_version: '13.2.0',
        sdk_version: '23.7.3', math_backend: 'OpenBLAS' }
    end

    it 'fulfills a pending claim when claim.id is supplied' do
      claim = create(:claim, computer: computer, commit: commit,
                             expires_at: 10.minutes.from_now)
      post '/submissions/create.json', params: {
        submitter: valid_submitter,
        commit: valid_commit,
        claim: { id: claim.id,
                 started_at: '2026-05-28T10:00:00Z',
                 use_fpe: true }
      }, as: :json

      expect(response).to have_http_status(:created)
      expect(claim.reload.status).to eq('fulfilled')
      expect(claim.fulfilled_at).to be_within(2.seconds).of(Time.current)

      submission = Submission.last
      expect(submission.claim_id).to eq(claim.id)
      expect(submission.use_fpe).to be true
      expect(submission.started_at).to be_within(1.second)
        .of(Time.zone.parse('2026-05-28T10:00:00Z'))
    end

    it 'reactivates an already-expired claim (late submission)' do
      # A test that took longer than the 12h TTL: the sweeper flipped
      # the claim to `expired`, but when the submission finally
      # arrives we should still credit it.
      claim = create(:claim, :expired,
                     computer: computer, commit: commit)
      post '/submissions/create.json', params: {
        submitter: valid_submitter,
        commit: valid_commit,
        claim: { id: claim.id }
      }, as: :json

      expect(response).to have_http_status(:created)
      expect(claim.reload.status).to eq('fulfilled')
      expect(claim.fulfilled_at).to be_within(2.seconds).of(Time.current)
    end

    it 'is a no-op when the submission carries no claim block (legacy client)' do
      pre_claim = create(:claim, computer: computer, commit: commit)

      post '/submissions/create.json', params: {
        submitter: valid_submitter,
        commit: valid_commit
      }, as: :json

      expect(response).to have_http_status(:created)
      expect(pre_claim.reload.status).to eq('pending')
      expect(Submission.last.claim_id).to be_nil
    end

  end

  describe 'GET /submissions/request_commit.json' do
    let(:user) { create(:user, password: 'pw-12345678', password_confirmation: 'pw-12345678') }
    let(:computer) { create(:computer, user: user) }

    it 'returns "no untested commits" when there are none' do
      get '/submissions/request_commit.json', params: {
        submitter: { email: user.email, password: 'pw-12345678',
                     computer: computer.name },
        commit: { sha: '' },
        max_age: 1
      }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to have_key('error')
      expect(body['error']).to match(/No untested commits/i)
    end

    it 'rejects unauthenticated requests' do
      get '/submissions/request_commit.json', params: {
        submitter: { email: 'nope@example.com', password: 'whatever',
                     computer: 'no-host' },
        commit: { sha: '' },
        max_age: 1
      }

      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
