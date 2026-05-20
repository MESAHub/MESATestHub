require 'rails_helper'
require 'openssl'

RSpec.describe 'GitHub webhooks', type: :request do
  include ActiveJob::TestHelper

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
  end

  def signature_for(body)
    'sha256=' + OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha256'), secret, body)
  end

  it 'accepts a valid push event and enqueues the branch sync job' do
    expect {
      post '/github_webhooks', params: payload,
                               headers: {
                                 'Content-Type' => 'application/json',
                                 'X-GitHub-Event' => 'push',
                                 'X-Hub-Signature-256' => signature_for(payload)
                               }
    }.to have_enqueued_job(BranchSyncJob)

    expect(response).to have_http_status(:ok)
  end

  it 'does not call Branch.api_update_branches inline during the request' do
    # The whole point of the job indirection is that the controller returns
    # before the GitHub sync happens. If someone deletes the job and puts
    # the inline call back, the webhook will start timing out on big pushes.
    allow(Branch).to receive(:api_update_branches)

    post '/github_webhooks', params: payload,
                             headers: {
                               'Content-Type' => 'application/json',
                               'X-GitHub-Event' => 'push',
                               'X-Hub-Signature-256' => signature_for(payload)
                             }

    expect(Branch).not_to have_received(:api_update_branches)
  end

  it 'executes Branch.api_update_branches when the queued job runs' do
    allow(Branch).to receive(:api_update_branches)

    perform_enqueued_jobs do
      post '/github_webhooks', params: payload,
                               headers: {
                                 'Content-Type' => 'application/json',
                                 'X-GitHub-Event' => 'push',
                                 'X-Hub-Signature-256' => signature_for(payload)
                               }
    end

    expect(Branch).to have_received(:api_update_branches)
  end

  # The github_webhook gem signals signature failures by raising
  # AbstractController::ActionNotFound. In production Rails converts that to a
  # 404; in the test environment it propagates, which is fine for our purposes
  # — we just need to confirm the bad payload is rejected and never reaches
  # the sync code path.
  it 'rejects requests with an invalid signature' do
    expect {
      expect {
        post '/github_webhooks', params: payload,
                                 headers: {
                                   'Content-Type' => 'application/json',
                                   'X-GitHub-Event' => 'push',
                                   'X-Hub-Signature-256' => 'sha256=' + 'f' * 64
                                 }
      }.to raise_error(AbstractController::ActionNotFound)
    }.not_to have_enqueued_job(BranchSyncJob)
  end

  it 'rejects requests with no signature header' do
    expect {
      expect {
        post '/github_webhooks', params: payload,
                                 headers: {
                                   'Content-Type' => 'application/json',
                                   'X-GitHub-Event' => 'push'
                                 }
      }.to raise_error(AbstractController::ActionNotFound)
    }.not_to have_enqueued_job(BranchSyncJob)
  end

  it 'accepts a ping event without enqueuing a sync job' do
    ping_payload = { zen: 'Practicality beats purity.', hook_id: 1 }.to_json

    expect {
      post '/github_webhooks', params: ping_payload,
                               headers: {
                                 'Content-Type' => 'application/json',
                                 'X-GitHub-Event' => 'ping',
                                 'X-Hub-Signature-256' => signature_for(ping_payload)
                               }
    }.not_to have_enqueued_job(BranchSyncJob)

    expect(response).to have_http_status(:ok)
  end
end
