require 'rails_helper'
require 'openssl'

RSpec.describe 'GitHub webhooks', type: :request do
  let(:secret) { 'test-webhook-secret' }
  let(:payload) do
    {
      ref: 'refs/heads/main',
      before: '0' * 40,
      after: 'a' * 40,
      repository: { full_name: 'MESAHub/mesa' },
      commits: []
    }.to_json
  end

  before do
    # The controller reads ENV['GITHUB_WEBHOOK_SECRET'] in webhook_secret(payload).
    stub_const('ENV', ENV.to_hash.merge('GITHUB_WEBHOOK_SECRET' => secret))
    # The push handler fans out to Branch.api_update_branches, which hits the
    # GitHub API. We're testing controller wiring, not the sync flow.
    allow(Branch).to receive(:api_update_branches).and_return(true)
  end

  def signature_for(body)
    'sha256=' + OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha256'), secret, body)
  end

  it 'accepts a valid push event and triggers the branch sync' do
    post '/github_webhooks', params: payload,
                             headers: {
                               'Content-Type' => 'application/json',
                               'X-GitHub-Event' => 'push',
                               'X-Hub-Signature-256' => signature_for(payload)
                             }

    expect(response).to have_http_status(:ok)
    expect(Branch).to have_received(:api_update_branches)
  end

  # The github_webhook gem signals signature failures by raising
  # AbstractController::ActionNotFound. In production Rails converts that to a
  # 404; in the test environment it propagates, which is fine for our purposes
  # — we just need to confirm the bad payload is rejected and never reaches
  # the sync code path.
  it 'rejects requests with an invalid signature' do
    expect {
      post '/github_webhooks', params: payload,
                               headers: {
                                 'Content-Type' => 'application/json',
                                 'X-GitHub-Event' => 'push',
                                 'X-Hub-Signature-256' => 'sha256=' + 'f' * 64
                               }
    }.to raise_error(AbstractController::ActionNotFound)
    expect(Branch).not_to have_received(:api_update_branches)
  end

  it 'rejects requests with no signature header' do
    expect {
      post '/github_webhooks', params: payload,
                               headers: {
                                 'Content-Type' => 'application/json',
                                 'X-GitHub-Event' => 'push'
                               }
    }.to raise_error(AbstractController::ActionNotFound)
    expect(Branch).not_to have_received(:api_update_branches)
  end

  it 'accepts a ping event without triggering branch sync' do
    ping_payload = { zen: 'Practicality beats purity.', hook_id: 1 }.to_json

    post '/github_webhooks', params: ping_payload,
                             headers: {
                               'Content-Type' => 'application/json',
                               'X-GitHub-Event' => 'ping',
                               'X-Hub-Signature-256' => signature_for(ping_payload)
                             }

    expect(response).to have_http_status(:ok)
    expect(Branch).not_to have_received(:api_update_branches)
  end
end
