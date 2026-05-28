require 'rails_helper'

# Phase B request specs for the claim-creation endpoint
# (docs/dispatcher-and-claims.md). Authentication mirrors the
# legacy submissions endpoint exactly so mesa_test reuses its
# existing credential plumbing; the request-body shape is new and
# nested under `submitter:` + `claim:` to leave room for the
# dispatcher endpoint that follows in Phase C.
RSpec.describe 'POST /api/v1/claims', type: :request do
  let(:user) do
    create(:user, password: 'pw-12345678',
                  password_confirmation: 'pw-12345678')
  end
  let(:computer) { create(:computer, user: user) }
  let(:commit)   { create(:commit) }
  let(:test_case) do
    create(:test_case, name: 'wd_planetary_companion', module: 'binary')
  end
  let(:tcc)      { create(:test_case_commit, commit: commit, test_case: test_case) }

  let(:valid_submitter) do
    { email: user.email, password: 'pw-12345678', computer: computer.name }
  end

  describe 'build scope' do
    let(:body) do
      {
        submitter: valid_submitter,
        claim: {
          commit_sha: commit.sha,
          scope: 'build',
          use_full_inlists: true
        }
      }
    end

    it 'creates a pending build-scope claim and returns id + expires_at' do
      expect { post '/api/v1/claims', params: body, as: :json }
        .to change(Claim, :count).by(1)

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json).to have_key('claim_id')
      expect(json).to have_key('expires_at')

      claim = Claim.find(json['claim_id'])
      expect(claim.scope).to eq('build')
      expect(claim.status).to eq('pending')
      expect(claim.computer).to eq(computer)
      expect(claim.commit).to eq(commit)
      expect(claim.test_case_commit).to be_nil
      expect(claim.use_full_inlists).to be true
      expect(claim.expires_at).to be_within(5.seconds).of(15.minutes.from_now)
    end
  end

  describe 'test scope' do
    let(:body) do
      {
        submitter: valid_submitter,
        claim: {
          commit_sha: commit.sha,
          scope: 'test',
          test_case_module: tcc.test_case.module,
          test_case_name:   tcc.test_case.name
        }
      }
    end

    it 'creates a pending test-scope claim linked to the matching TCC' do
      # Pre-load the TCC to make sure it's resolvable by the lookup
      tcc

      expect { post '/api/v1/claims', params: body, as: :json }
        .to change(Claim, :count).by(1)

      expect(response).to have_http_status(:created)
      claim = Claim.last
      expect(claim.scope).to eq('test')
      expect(claim.test_case_commit).to eq(tcc)
      expect(claim.expires_at).to be_within(5.seconds).of(12.hours.from_now)
    end

    it 'echoes dispatched_at when the request supplies one' do
      tcc
      dispatched_at = '2026-05-28T10:00:00Z'
      post '/api/v1/claims',
           params: body.deep_merge(claim: { dispatched_at: dispatched_at }),
           as: :json

      expect(response).to have_http_status(:created)
      claim = Claim.last
      expect(claim.dispatched_at).to be_within(1.second)
        .of(Time.zone.parse(dispatched_at))
    end

    it 'returns 404 when the test case does not exist on this commit' do
      tcc
      post '/api/v1/claims',
           params: body.deep_merge(claim: { test_case_name: 'nope_not_here' }),
           as: :json

      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)).to have_key('error')
      expect(Claim.count).to eq(0)
    end

    it 'rejects test-scope claims missing the test_case_module/name pair' do
      post '/api/v1/claims',
           params: { submitter: valid_submitter,
                     claim: { commit_sha: commit.sha, scope: 'test' } },
           as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)['error']).to match(/test_case_/)
      expect(Claim.count).to eq(0)
    end
  end

  describe 'validation failures' do
    it 'rejects an unknown scope' do
      post '/api/v1/claims', params: {
        submitter: valid_submitter,
        claim: { commit_sha: commit.sha, scope: 'audit' }
      }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)['error']).to match(/scope/i)
      expect(Claim.count).to eq(0)
    end

    it 'returns 404 for an unknown commit SHA' do
      post '/api/v1/claims', params: {
        submitter: valid_submitter,
        claim: { commit_sha: 'deadbeef' * 5, scope: 'build' }
      }, as: :json

      expect(response).to have_http_status(:not_found)
      expect(Claim.count).to eq(0)
    end
  end

  describe 'authentication failures' do
    it 'rejects an unknown user' do
      post '/api/v1/claims', params: {
        submitter: { email: 'nope@example.com', password: 'pw',
                     computer: computer.name },
        claim: { commit_sha: commit.sha, scope: 'build' }
      }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)['error']).to match(/Invalid e-mail/)
      expect(Claim.count).to eq(0)
    end

    it 'rejects a wrong password' do
      post '/api/v1/claims', params: {
        submitter: valid_submitter.merge(password: 'wrong'),
        claim: { commit_sha: commit.sha, scope: 'build' }
      }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)['error']).to match(/Invalid e-mail/)
    end

    it "rejects a computer the authenticated user doesn't own" do
      other_user = create(:user)
      other_computer = create(:computer, user: other_user, name: 'other-host')

      post '/api/v1/claims', params: {
        submitter: valid_submitter.merge(computer: other_computer.name),
        claim: { commit_sha: commit.sha, scope: 'build' }
      }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)['error']).to match(/doesn't control/)
      expect(Claim.count).to eq(0)
    end
  end
end
