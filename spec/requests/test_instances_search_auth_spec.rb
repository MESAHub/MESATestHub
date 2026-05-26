require 'rails_helper'

# Auth boundary for test_instances#search.
#
# Background: in 2019 (commit 6112b7f) the JSON variant of this
# action was given a stateless `email` + `password` auth path so
# CLI clients like `mesa_test` could pull past test instances
# without a browser session. In September 2025 (commit b8542bc) a
# global `authorize_user` before_action went into ApplicationController
# to reduce anonymous browse traffic, but the curated skip list
# omitted this controller — silently 302-ing every external API
# caller to /login.
#
# This spec locks in the corrected behaviour:
#   - HTML format stays behind the login wall (preserves b8542bc's intent)
#   - JSON format bypasses the global filter and authenticates per
#     request via the action's own `authenticated?` helper
#   - The JSON-only `search_count` always authenticates per request
RSpec.describe 'Auth boundary for /test_instances/search', type: :request do
  let(:password) { 'pw-12345678' }
  let(:user) do
    create(:user, password: password, password_confirmation: password)
  end

  describe 'HTML format (browser path)' do
    it 'redirects anonymous users to the login page' do
      get '/test_instances/search'
      expect(response).to redirect_to(login_path)
    end

    it 'lets authenticated users render the page' do
      post '/sessions', params: { email: user.email, password: password }
      get '/test_instances/search'
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'JSON format (mesa_test / CLI path)' do
    it 'accepts a stateless email + password and returns results, not a 302' do
      get '/test_instances/search.json',
          params: { email: user.email, password: password, query_text: 'passed: true' }

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to start_with('application/json')
      body = JSON.parse(response.body)
      expect(body).to include('results', 'failures')
    end

    it 'returns a JSON error (not a redirect) when no credentials are given' do
      get '/test_instances/search.json', params: { query_text: 'passed: true' }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.content_type).to start_with('application/json')
      expect(JSON.parse(response.body)).to include('error')
    end

    it 'returns a JSON error when the email/password are wrong' do
      get '/test_instances/search.json',
          params: { email: user.email, password: 'wrong-password',
                    query_text: 'passed: true' }

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)).to include('error')
    end

    it 'also accepts a browser session (no params needed)' do
      post '/sessions', params: { email: user.email, password: password }
      get '/test_instances/search.json', params: { query_text: 'passed: true' }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to include('results', 'failures')
    end
  end

  describe 'JSON format (search_count)' do
    it 'accepts a stateless email + password' do
      get '/test_instances/search_count.json',
          params: { email: user.email, password: password, query_text: 'passed: true' }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to include('count', 'failures')
    end

    it 'returns a JSON error (not a redirect) when unauthenticated' do
      get '/test_instances/search_count.json', params: { query_text: 'passed: true' }

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)).to include('error')
    end
  end
end
