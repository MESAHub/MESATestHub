require 'rails_helper'

# Every client-facing endpoint accepts a per-computer API key in
# `Authorization: Bearer`, and still accepts the legacy email +
# password (docs/api-keys.md). A request that sends a key is judged
# on the key alone.
RSpec.describe 'API key authentication', type: :request do
  let(:password) { 'pw-12345678' }
  let(:user)     { create(:user, password: password, password_confirmation: password) }
  let(:computer) { create(:computer, user: user) }
  let!(:key)     { computer.generate_api_key! }
  let(:auth)     { { 'Authorization' => "Bearer #{key}" } }
  let(:bad_auth) { { 'Authorization' => 'Bearer mth_nope' } }
  let(:password_submitter) { { email: user.email, password: password, computer: computer.name } }

  let(:main) { create(:branch, name: 'main') }
  let!(:commit) do
    create(:commit, commit_time: 1.hour.ago).tap do |c|
      BranchMembership.create!(branch: main, commit: c)
      main.update!(head: c)
    end
  end
  let(:build_commit) do
    { sha: commit.sha, entire: false, empty: true, compiled: true,
      compiler: 'gfortran', compiler_version: '13.2.0' }
  end

  def json
    JSON.parse(response.body)
  end

  describe 'POST /submissions/create.json' do
    it 'accepts a key with no submitter block, and records last use' do
      post '/submissions/create.json', params: { commit: build_commit }, headers: auth, as: :json

      expect(response).to have_http_status(:created)
      expect(Submission.last.computer).to eq(computer)
      expect(computer.reload.api_key_last_used_at).to be_present
    end

    it 'accepts a key alongside a submitter block naming the same computer' do
      post '/submissions/create.json',
           params: { submitter: { computer: computer.name, platform_version: '15.1' },
                     commit: build_commit },
           headers: auth, as: :json

      expect(response).to have_http_status(:created)
      expect(Submission.last.platform_version).to eq('15.1')
    end

    it 'refuses a key whose computer differs from the named one' do
      post '/submissions/create.json',
           params: { submitter: { computer: create(:computer, user: user).name },
                     commit: build_commit },
           headers: auth, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json['error']).to include(computer.name)
      expect(Submission.count).to eq(0)
    end

    it 'refuses an unknown key without falling back to a valid password' do
      post '/submissions/create.json',
           params: { submitter: password_submitter, commit: build_commit },
           headers: bad_auth, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(json['error']).to eq('Invalid API key.')
      expect(Submission.count).to eq(0)
    end

    it 'still accepts email + password with no key' do
      post '/submissions/create.json',
           params: { submitter: password_submitter, commit: build_commit }, as: :json

      expect(response).to have_http_status(:created)
    end
  end

  describe 'GET /submissions/request_commit.json' do
    it 'accepts a key' do
      get '/submissions/request_commit.json', params: { max_age: 2 }, headers: auth

      expect(response).to have_http_status(:ok)
      expect(json['sha']).to eq(commit.sha)
    end
  end

  describe 'POST /api/v1/claims and /api/v1/dispatch' do
    it 'creates a claim with a key alone' do
      post '/api/v1/claims', params: { claim: { commit_sha: commit.sha, scope: 'build' } },
                             headers: auth, as: :json

      expect(response).to have_http_status(:created)
      expect(Claim.last.computer).to eq(computer)
    end

    it 'dispatches with a key alone' do
      post '/api/v1/dispatch', params: { dispatch: { scope: 'build' } }, headers: auth, as: :json

      expect(response).to have_http_status(:ok)
      expect(json['commit_sha']).to eq(commit.sha)
    end

    it 'refuses an unknown key' do
      post '/api/v1/dispatch', params: { submitter: password_submitter, dispatch: { scope: 'build' } },
                               headers: bad_auth, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'still accepts email + password' do
      post '/api/v1/dispatch', params: { submitter: password_submitter, dispatch: { scope: 'build' } },
                               as: :json

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'search and count' do
    it 'accepts a key in place of email + password' do
      get '/test_instances/search.json', params: { query_text: 'passed: true' }, headers: auth
      expect(response).to have_http_status(:ok)
      expect(json).to include('results', 'failures')

      get '/test_instances/search_count.json', params: { query_text: 'passed: true' }, headers: auth
      expect(response).to have_http_status(:ok)
      expect(json).to include('count')
    end

    it 'refuses an unknown key even with a valid password' do
      get '/test_instances/search_count.json',
          params: { email: user.email, password: password, query_text: 'passed: true' },
          headers: bad_auth

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST /check_computer.json' do
    it 'confirms a valid key and names its computer' do
      post '/check_computer.json', headers: auth

      expect(json).to include('valid' => true, 'computer' => computer.name)
    end

    it 'flags a key for a different computer than the one named' do
      post '/check_computer.json', params: { computer_name: 'elsewhere' }, headers: auth

      expect(json['valid']).to be false
    end

    it 'rejects an unknown key' do
      post '/check_computer.json', headers: bad_auth

      expect(json['valid']).to be false
    end

    it 'still checks email + password + computer name' do
      post '/check_computer.json',
           params: { email: user.email, password: password, computer_name: computer.name },
           as: :json

      expect(json['valid']).to be true
    end
  end
end
