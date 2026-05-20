class BranchSyncJob < ApplicationJob
  queue_as :default

  # Webhooks fire BranchSyncJob to keep the controller off the GitHub API
  # critical path. The job itself runs Branch.api_update_branches, which
  # is idempotent — running it twice produces the same end state — so we
  # don't bother deduplicating overlapping enqueues at this layer.
  def perform
    Branch.api_update_branches
  end
end
