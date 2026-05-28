class ClaimSweeperJob < ApplicationJob
  queue_as :default

  # Forward-transition pending claims past their expires_at to
  # expired. Fired every ~5 min from config/recurring.yml so the
  # commits-index "pending" tile stays wall-clock-accurate. Cheap:
  # one indexed UPDATE backed by index_claims_on_expires_at_pending.
  # The rake task claims:sweep remains as the manual/debugging entry
  # point. See docs/dispatcher-and-claims.md.
  def perform
    Claim.sweep_expired!
  end
end
