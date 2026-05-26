require 'rails_helper'

# JSON-API surface for `test_instances#search`. The query parser
# itself is covered exhaustively by `spec/models/test_instance_query_spec.rb`;
# this file's job is to lock in that both the HTML and JSON formats
# pass user input through the same `TestInstance.query` pipeline,
# and that the JSON envelope (`results` + `failures`) carries the
# new `branch:` filter and the full-SHA `commit:` fix end-to-end.
#
# These tests use a browser-style session (POST /sessions then
# follow-up GETs reuse the cookie). The controller advertises a
# stateless email/password fallback inside `authenticated?`, but
# the global `authorize_user` before_action redirects unauthenticated
# callers before the action body ever runs — so that fallback is
# effectively dead code. Reaching the JSON endpoint without a
# session is a separate concern; this spec exercises the path that
# does work.
RSpec.describe 'GET /test_instances/search.json', type: :request do
  let(:user) do
    create(:user, password: 'pw-12345678', password_confirmation: 'pw-12345678')
  end
  let(:test_case)      { create(:test_case) }
  let(:computer)       { create(:computer, user: user) }
  let(:main_branch)    { create(:branch, name: 'main') }
  let(:feature_branch) { create(:branch, name: 'feature-x') }
  let(:main_commit)    { create(:commit) }
  let(:feature_commit) { create(:commit) }

  before do
    BranchMembership.create!(branch: main_branch,    commit: main_commit)
    BranchMembership.create!(branch: feature_branch, commit: feature_commit)
    post '/sessions', params: { email: user.email, password: 'pw-12345678' }
  end

  def make_instance(commit:)
    submission = create(:submission, commit: commit, computer: computer)
    create(:test_instance, commit: commit, computer: computer,
                           test_case: test_case, submission: submission)
  end

  let!(:main_instance)    { make_instance(commit: main_commit) }
  let!(:feature_instance) { make_instance(commit: feature_commit) }

  it 'filters by branch through the JSON endpoint' do
    get '/test_instances/search.json', params: { query_text: 'branch: main' }

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body['failures']).to be_empty
    expect(body['results'].size).to eq(1)
  end

  it 'reports unknown branches in the failures array without raising' do
    get '/test_instances/search.json',
        params: { query_text: 'branch: no-such-branch' }

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body['results']).to be_empty
    expect(body['failures']).to include(a_string_starting_with('branch (no-such-branch'))
  end

  it 'resolves a full 40-char SHA through the JSON endpoint' do
    get '/test_instances/search.json',
        params: { query_text: "commit: #{main_commit.sha}" }

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body['failures']).to be_empty
    expect(body['results'].size).to eq(1)
  end

  it 'composes branch with the rest of the query language' do
    get '/test_instances/search.json',
        params: { query_text: "branch: main; computer: #{computer.name}" }

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body['failures']).to be_empty
    expect(body['results'].size).to eq(1)
  end

  describe 'GET /test_instances/search_count.json' do
    it 'returns the count for a branch query' do
      get '/test_instances/search_count.json',
          params: { query_text: 'branch: main' }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['failures']).to be_empty
      expect(body['count']).to eq(1)
    end
  end
end
