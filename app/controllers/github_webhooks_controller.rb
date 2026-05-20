class GithubWebhooksController < ApplicationController
  skip_before_action :authorize_user
  skip_before_action :verify_authenticity_token, only: [:create]

  include GithubWebhook::Processor

  # Handle push event by kicking off a background sync. Returning quickly
  # matters: GitHub considers a webhook delivery failed after 10 seconds,
  # and the inline sync can take much longer than that on a large push.
  #
  # We forward only the fields BranchSyncJob actually uses; the full
  # payload is much larger and would bloat the job queue with data we
  # don't need (repository metadata, pusher info, head_commit duplicate
  # of the last commits[] entry, etc.).
  def github_push(payload)
    data = payload.to_h.slice(
      'ref', 'before', 'after', 'created', 'deleted', 'forced', 'commits'
    )
    BranchSyncJob.perform_later(data)
  end

  private

  def webhook_secret(payload)
    ENV['GITHUB_WEBHOOK_SECRET']
  end
end
