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

    it 'rejects submissions with an invalid password' do
      post '/submissions/create.json',
           params: {
             submitter: valid_submitter.merge(password: 'wrong-password'),
             commit: valid_commit
           },
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
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

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Submission.count).to eq(0)
    end

    it 'rejects submissions for an unknown computer name' do
      post '/submissions/create.json',
           params: {
             submitter: valid_submitter.merge(computer: 'nonexistent-host'),
             commit: valid_commit
           },
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
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

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Submission.count).to eq(0)
    end
  end

  describe 'GET /submissions/request_commit.json' do
    let(:user) { create(:user, password: 'pw-12345678', password_confirmation: 'pw-12345678') }
    let(:computer) { create(:computer, user: user) }

    it 'returns "no untested commits" when there are none' do
      # Bypass Commit.test_candidate — it has a separate recursion bug when
      # no Branch.main exists, which is a Phase 3 cleanup target.
      allow(Commit).to receive(:test_candidate).and_return(nil)

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

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
