class GithubWebhooksController < ApplicationController

  skip_before_action :verify_authenticity_token, only: [:create]

  include GithubWebhook::Processor

  # Handle push event
  def github_push(payload)
    # Create new entry in database for each new commit in push
    Commit.push_update(payload)
  end

  private

  def webhook_secret(payload)
    # hard-coded for now, but this needs to go into an environment variable
    'Betelgeuse3x'
    # ENV['GITHUB_WEBHOOK_SECRET']
  end
end
