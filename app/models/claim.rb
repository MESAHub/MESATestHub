# Records a computer's intent to do a specific piece of work
# (`scope='build'`: build a commit; `scope='test'`: run a single
# test case on a commit). See docs/dispatcher-and-claims.md for
# the design.
#
# Phase A's claim is purely a data object — the dispatcher and
# expiry sweeper that operate on it land in Phases B and C. The
# model carries the validations + associations needed so a row is
# always self-consistent: scope/TCC coherence, and the invariant
# that a test-scope claim's TCC belongs to the same commit the
# claim points at.
#
# The CHECK constraint `claims_scope_fk_coherence` enforces the
# scope/TCC pairing at the database level; the model validation is
# the friendly user-facing version (returns a validation error
# instead of raising a Postgres exception).
class Claim < ApplicationRecord
  SCOPES   = %w[build test].freeze
  STATUSES = %w[pending fulfilled expired].freeze

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
