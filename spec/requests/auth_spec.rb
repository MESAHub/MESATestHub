require 'rails_helper'

RSpec.describe 'Authentication flow', type: :request do
  describe 'POST /sessions' do
    let!(:user) { create(:user, password: 'correct-horse', password_confirmation: 'correct-horse') }

    it 'logs the user in with valid credentials' do
      post '/sessions', params: { email: user.email, password: 'correct-horse' }

      expect(response).to redirect_to(root_url)
      expect(session[:user_id]).to eq(user.id)
    end

    it 'rejects invalid passwords without setting a session' do
      post '/sessions', params: { email: user.email, password: 'wrong-password' }

      expect(response).to have_http_status(:ok) # renders 'new' template with flash
      expect(session[:user_id]).to be_nil
      expect(response.body).to include('invalid')
    end

    it 'rejects unknown emails without setting a session' do
      post '/sessions', params: { email: 'nope@example.com', password: 'whatever' }

      expect(session[:user_id]).to be_nil
    end
  end

  describe 'GET /logout' do
    let!(:user) { create(:user) }

    it 'clears the session' do
      post '/sessions', params: { email: user.email, password: user.password }
      expect(session[:user_id]).to eq(user.id)

      get '/logout'
      expect(response).to redirect_to(root_url)
      expect(session[:user_id]).to be_nil
    end
  end

  describe 'protected resources' do
    it 'redirects unauthenticated requests for /users to login' do
      get '/users'

      expect(response).to redirect_to(login_url)
    end

    it 'allows authenticated requests to reach /users' do
      user = create(:user)
      post '/sessions', params: { email: user.email, password: user.password }

      get '/users'
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'POST /check_user (JSON credential check)' do
    let!(:user) { create(:user, password: 'sekrit-pw', password_confirmation: 'sekrit-pw') }

    it 'returns valid: true for correct credentials' do
      post '/check_user', params: { email: user.email, password: 'sekrit-pw' },
                          as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['valid']).to eq(true)
    end

    it 'returns valid: false for incorrect credentials' do
      post '/check_user', params: { email: user.email, password: 'wrong-pw' },
                          as: :json

      body = JSON.parse(response.body)
      expect(body['valid']).to eq(false)
    end
  end
end
