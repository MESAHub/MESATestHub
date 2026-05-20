class GithubWebhooksController < ApplicationController
  skip_before_action :authorize_user
  skip_before_action :verify_authenticity_token, only: [:create]

  include GithubWebhook::Processor

  # Handle push event by kicking off a background sync. Returning quickly
  # matters: GitHub considers a webhook delivery failed after 10 seconds,
  # and the inline sync can take much longer than that on a large push.
  def github_push(payload)
    BranchSyncJob.perform_later
  end

  private

  def webhook_secret(payload)
    ENV['GITHUB_WEBHOOK_SECRET']
  end
end
