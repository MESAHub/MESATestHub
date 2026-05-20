require 'rails_helper'

RSpec.describe Commit, type: :model do
  describe '.test_candidate' do
    let(:user) { create(:user) }
    let(:computer) { create(:computer, user: user) }

    context 'when no main branch exists' do
      it 'does not infinite-recurse and returns nil when nothing matches' do
        # Regression: previously, with no Branch.main, the unbranched call
        # would recurse with branch: Branch.main (= nil), re-enter the
        # else arm, call Branch.main again, and spin forever.
        expect { Timeout.timeout(2) { Commit.test_candidate(computer: computer) } }
          .not_to raise_error
        expect(Commit.test_candidate(computer: computer)).to be_nil
      end

      it 'still returns a commit from a non-main branch when one is available' do
        other_branch = create(:branch, name: 'feature-x')
        commit = create(:commit)
        BranchMembership.create!(branch: other_branch, commit: commit)

        result = Timeout.timeout(2) { Commit.test_candidate(computer: computer) }
        expect(result).to eq(commit)
      end
    end

    context 'when a main branch exists' do
      it 'prefers a candidate on main over other branches' do
        main = create(:branch, name: 'main')
        other = create(:branch, name: 'feature-y')

        main_commit = create(:commit)
        other_commit = create(:commit)
        BranchMembership.create!(branch: main, commit: main_commit)
        BranchMembership.create!(branch: other, commit: other_commit)

        expect(Commit.test_candidate(computer: computer)).to eq(main_commit)
      end
    end
  end
end
