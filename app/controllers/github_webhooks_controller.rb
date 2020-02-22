class GithubWebhooksController < ApplicationController
  include GithubWebhook::Processor

  # Handle push event
  def github_push(payload)
    # update the local [mirror] repo
    Commit.fetch
    # Create new entry in database for each new commit in push
    Commit.batch_create(payload[:commits].map { |commit| commit[:sha] })
  end

  private

  def webhook_secret(payload)
    # hard-coded for now, but this needs to go into an environment variable
    'Betelgeuse3x'
    # ENV['GITHUB_WEBHOOK_SECRET']
  end
end
