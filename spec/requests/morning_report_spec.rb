require 'rails_helper'

RSpec.describe 'Morning report page', type: :request do
  let(:user) { create(:user, password: 'pw-12345678', password_confirmation: 'pw-12345678') }

  describe 'GET /morning_report' do
    it 'redirects unauthenticated visitors to login' do
      get '/morning_report'
      expect(response).to redirect_to(login_path)
    end

    context 'when signed in' do
      before do
        post '/sessions', params: { email: user.email, password: 'pw-12345678' }
      end

      it 'renders the empty-state digest' do
        get '/morning_report'
        expect(response).to have_http_status(:ok)
        flat = response.body.gsub(/\s+/, ' ')
        expect(flat).to include('Daily digest')
        expect(flat).to include('No new test runs in the last 24 hours')
      end

      it 'accepts a ?date= query for historical reports' do
        get '/morning_report', params: { date: '2025-01-15' }
        expect(response).to have_http_status(:ok)
      end
    end
  end
end
