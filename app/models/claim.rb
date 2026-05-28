# Records a computer's intent to do a specific piece of work
# (`scope='build'`: build a commit; `scope='test'`: run a single
# test case on a commit). See docs/dispatcher-and-claims.md for
# the design.
#
# Created via POST /api/v1/claims (Phase B) — the controller writes
# the row and starts the wall-clock TTL via
# `Claim.default_expires_at`. Fulfilled by an `after_create_commit`
# callback on Submission when a submission arrives carrying the
# claim's id; the same callback handles the `expired → fulfilled`
# transition for legitimately-late submissions. Pending claims past
# `expires_at` get swept to `expired` by `rake claims:sweep`.
#
# The CHECK constraint `claims_scope_fk_coherence` enforces the
# scope/TCC pairing at the database level; the model validation is
# the friendly user-facing version (returns a validation error
# instead of raising a Postgres exception).
class Claim < ApplicationRecord
  SCOPES   = %w[build test].freeze
  STATUSES = %w[pending fulfilled expired].freeze

  # V1 TTLs (docs/dispatcher-and-claims.md "TTLs"): builds are
  # always quick, so 15 min is plenty; tests can legitimately run
  # for hours, and short TTLs would produce noisy false
  # expirations. Phase E swaps the test side for a historical-
  # runtime calculation; the build side stays fixed because the
  # easy case doesn't need help.
  TTL_FOR_SCOPE = {
    'build' => 15.minutes,
    'test'  => 12.hours
  }.freeze

  belongs_to :computer
  belongs_to :commit
  belongs_to :test_case_commit, optional: true

  has_one :submission, dependent: :nullify

  validates :scope,      inclusion: { in: SCOPES }
  validates :status,     inclusion: { in: STATUSES }
  validates :expires_at, presence: true

  validate :scope_and_tcc_coherent
  validate :tcc_commit_matches_claim_commit

  scope :pending,   -> { where(status: 'pending') }
  scope :fulfilled, -> { where(status: 'fulfilled') }
  scope :expired,   -> { where(status: 'expired') }

  # Wall-clock expiration for a freshly-created claim. The TTL
  # constants live on this model so the controller doesn't
  # duplicate them at the HTTP boundary.
  def self.default_expires_at(scope:)
    TTL_FOR_SCOPE.fetch(scope).from_now
  end

  # Forward-transition `pending → expired` for every claim whose
  # `expires_at` has passed. Bulk UPDATE backed by
  # `index_claims_on_expires_at_pending` (the partial index on
  # `expires_at` scoped to `status = 'pending'`). Driven by
  # `rake claims:sweep` from Railway cron; safe to call any time,
  # including in-process from a spec.
  #
  # Returns the number of rows transitioned. Does NOT touch
  # `fulfilled` claims (a late-submission reactivation isn't an
  # expiration) or claims already swept.
  def self.sweep_expired!(now: Time.current)
    pending.where('expires_at < ?', now)
           .update_all(status: 'expired', updated_at: now)
  end

  # Flip the claim to `fulfilled`. Idempotent across the two legal
  # starting states (pending OR expired) — a late submission that
  # arrives after the sweeper has flipped the claim to `expired`
  # legitimately flips it back to `fulfilled` (lifecycle diagram in
  # docs/dispatcher-and-claims.md). Uses update_columns so a stale
  # `updated_at` race against the sweeper can't reject the write,
  # and so AR validations on `status` never see the transient state.
  def fulfill!(at: Time.current)
    update_columns(status: 'fulfilled',
                   fulfilled_at: at,
                   updated_at: Time.current)
  end

  private

  # Mirrors the `claims_scope_fk_coherence` CHECK constraint, but
  # surfaces as an ActiveRecord validation error so callers see
  # `Claim#errors` rather than an `ActiveRecord::StatementInvalid`.
  def scope_and_tcc_coherent
    case scope
    when 'build'
      if test_case_commit_id.present?
        errors.add(:test_case_commit_id,
                   "must be blank for build-scope claims")
      end
    when 'test'
      if test_case_commit_id.blank?
        errors.add(:test_case_commit_id,
                   "is required for test-scope claims")
      end
    end
  end

  # `commit_id` is denormalized on every claim row so "all claims
  # on this SHA" is a single index lookup, not a join. That
  # convenience only holds if the claim's commit_id stays in sync
  # with its TCC's commit_id — guard it here.
  def tcc_commit_matches_claim_commit
    return unless scope == 'test'
    return if test_case_commit.blank?
    return if test_case_commit.commit_id == commit_id
    errors.add(:test_case_commit,
               "must belong to the claim's commit")
  end
end
