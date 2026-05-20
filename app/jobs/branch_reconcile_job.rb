class BranchReconcileJob < ApplicationJob
  queue_as :default

  # Thin wrapper around Branch.reconcile_with_github so the operation
  # can be enqueued from anywhere ActiveJob is wired up (admin endpoint,
  # scheduled task, ad hoc Rails runner). Returns the per-category
  # counts hash so a caller running it inline (perform_now) gets useful
  # output.
  def perform
    Branch.reconcile_with_github
  end
end
