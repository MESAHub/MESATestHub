require 'rails_helper'

# Generating, replacing, and revoking a computer's API key from its
# page (docs/api-keys.md). Owner or admin only; the plaintext is shown
# once, on the response to the generating POST.
RSpec.describe 'Computer API key management', type: :request do
  let(:password) { 'pw-12345678' }
  let(:owner)    { create(:user, password: password, password_confirmation: password) }
  let(:computer) { create(:computer, user: owner) }

  def log_in(user)
    post '/sessions', params: { email: user.email, password: password }
  end

  it 'shows the owner a Generate button, then the new key exactly once' do
    log_in(owner)
    get "/users/#{owner.id}/computers/#{computer.id}"
    expect(response.body).to include('Generate key')

    post "/users/#{owner.id}/computers/#{computer.id}/api_key"
    expect(response).to have_http_status(:ok)
    key = response.body[/mth_[A-Za-z0-9_\-]+/]
    expect(Computer.find_by_api_key(key)).to eq(computer)

    get "/users/#{owner.id}/computers/#{computer.id}"
    expect(response.body).not_to include(key)
    expect(response.body).to include(computer.reload.api_key_prefix)
    expect(response.body).to include('Revoke')
  end

  it 'sends a reload of the one-time page back to the computer page' do
    get "/users/#{owner.id}/computers/#{computer.id}/api_key"
    expect(response).to redirect_to("/users/#{owner.id}/computers/#{computer.id}")
  end

  it 'revokes the key' do
    key = computer.generate_api_key!
    log_in(owner)
    delete "/users/#{owner.id}/computers/#{computer.id}/api_key"

    expect(response).to redirect_to("/users/#{owner.id}/computers/#{computer.id}")
    expect(Computer.find_by_api_key(key)).to be_nil
  end

  it "doesn't let another user generate or revoke a key" do
    stranger = create(:user, password: password, password_confirmation: password)
    key = computer.generate_api_key!
    log_in(stranger)

    post "/users/#{owner.id}/computers/#{computer.id}/api_key"
    expect(response).to redirect_to(login_url)
    delete "/users/#{owner.id}/computers/#{computer.id}/api_key"
    expect(Computer.find_by_api_key(key)).to eq(computer)

    get "/users/#{owner.id}/computers/#{computer.id}"
    expect(response.body).not_to include('Generate key')
  end

  it 'lets an admin manage any computer' do
    admin = create(:user, password: password, password_confirmation: password, admin: true)
    log_in(admin)
    post "/users/#{owner.id}/computers/#{computer.id}/api_key"

    expect(computer.reload.api_key?).to be true
  end
end
