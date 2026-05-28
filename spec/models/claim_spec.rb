require 'rails_helper'

# Phase A spec: validates the Claim model's structural invariants —
# associations, enum-style inclusions, and the scope/TCC coherence
# rules that mirror the `claims_scope_fk_coherence` CHECK
# constraint in the database. The lifecycle behavior (expiration,
# fulfilling submissions) lands in Phase B.
RSpec.describe Claim, type: :model do
  let(:user)     { create(:user) }
  let(:computer) { create(:computer, user: user) }
  let(:commit)   { create(:commit) }
  let(:tcc)      { create(:test_case_commit, commit: commit) }

  describe 'validations' do
    it 'is valid for a minimal build-scope claim' do
      claim = build(:claim, computer: computer, commit: commit)
      expect(claim).to be_valid
    end

    it 'is valid for a test-scope claim with a matching TCC' do
      claim = build(:claim, :test_scope,
                    computer: computer, commit: commit,
                    test_case_commit: tcc)
      expect(claim).to be_valid
    end

    it 'rejects an unknown scope' do
      claim = build(:claim, computer: computer, commit: commit,
                            scope: 'audit')
      expect(claim).not_to be_valid
      expect(claim.errors[:scope]).to be_present
    end

    it 'rejects an unknown status' do
      claim = build(:claim, computer: computer, commit: commit,
                            status: 'whoops')
      expect(claim).not_to be_valid
      expect(claim.errors[:status]).to be_present
    end

    it 'requires expires_at' do
      claim = build(:claim, computer: computer, commit: commit,
                            expires_at: nil)
      expect(claim).not_to be_valid
      expect(claim.errors[:expires_at]).to be_present
    end

    it 'rejects a build-scope claim that carries a TCC' do
      claim = build(:claim, computer: computer, commit: commit,
                            scope: 'build', test_case_commit: tcc)
      expect(claim).not_to be_valid
      expect(claim.errors[:test_case_commit_id]).to be_present
    end

    it 'rejects a test-scope claim without a TCC' do
      claim = build(:claim, computer: computer, commit: commit,
                            scope: 'test', test_case_commit: nil)
      expect(claim).not_to be_valid
      expect(claim.errors[:test_case_commit_id]).to be_present
    end

    it "rejects a test-scope claim whose TCC belongs to a different commit" do
      other_commit = create(:commit)
      other_tcc    = create(:test_case_commit, commit: other_commit)

      claim = build(:claim, computer: computer, commit: commit,
                            scope: 'test', test_case_commit: other_tcc)
      expect(claim).not_to be_valid
      expect(claim.errors[:test_case_commit]).to be_present
    end
  end

  describe 'database-level scope/FK coherence' do
    # Belt-and-suspenders: the `claims_scope_fk_coherence` CHECK
    # backstops the model validations so direct SQL writes can't
    # produce an incoherent row.
    it 'raises when a build-scope row tries to carry a TCC' do
      expect {
        ActiveRecord::Base.connection.execute(<<~SQL)
          INSERT INTO claims
            (computer_id, commit_id, test_case_commit_id,
             scope, status, expires_at, created_at, updated_at)
          VALUES
            (#{computer.id}, #{commit.id}, #{tcc.id},
             'build', 'pending', NOW(), NOW(), NOW())
        SQL
      }.to raise_error(ActiveRecord::StatementInvalid, /claims_scope_fk_coherence/)
    end

    it 'raises when a test-scope row omits a TCC' do
      expect {
        ActiveRecord::Base.connection.execute(<<~SQL)
          INSERT INTO claims
            (computer_id, commit_id, test_case_commit_id,
             scope, status, expires_at, created_at, updated_at)
          VALUES
            (#{computer.id}, #{commit.id}, NULL,
             'test', 'pending', NOW(), NOW(), NOW())
        SQL
      }.to raise_error(ActiveRecord::StatementInvalid, /claims_scope_fk_coherence/)
    end
  end

  describe 'scopes' do
    it 'partitions rows by status' do
      pending   = create(:claim, computer: computer, commit: commit)
      fulfilled = create(:claim, :fulfilled, computer: computer,
                                              commit: commit)
      expired   = create(:claim, :expired, computer: computer,
                                            commit: commit)

      expect(Claim.pending).to   include(pending)
      expect(Claim.fulfilled).to include(fulfilled)
      expect(Claim.expired).to   include(expired)
    end
  end

  describe 'associations' do
    it 'destroys claims when the parent commit is destroyed' do
      claim = create(:claim, computer: computer, commit: commit)
      expect { commit.destroy }.to change(Claim, :count).by(-1)
    end

    it 'destroys claims when the parent computer is destroyed' do
      claim = create(:claim, computer: computer, commit: commit)
      expect { computer.destroy }.to change(Claim, :count).by(-1)
    end

    it 'nullifies the claim FK on its submission when the claim is destroyed' do
      claim = create(:claim, computer: computer, commit: commit)
      submission = create(:submission, computer: computer, commit: commit,
                                       claim: claim)
      expect { claim.destroy }.to change { submission.reload.claim_id }
        .from(claim.id).to(nil)
    end
  end
end
