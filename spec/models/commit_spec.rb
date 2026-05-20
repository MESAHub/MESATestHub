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

  describe 'flag predicates on commits with no test cases' do
    # Regression: each of run_optional?, fpe_checks?, fine_resolution?
    # used to return true on a commit with zero test cases because
    # `0 == 0` in `pluck(...).uniq.count == test_cases.count`. That
    # made every freshly-ingested commit on the index page light up
    # with the wrench / plus-square / search-plus icons.
    let(:commit) { create(:commit) }

    it 'run_optional? is false when there are no test cases' do
      expect(commit.test_cases).to be_empty
      expect(commit.run_optional?).to be false
    end

    it 'fpe_checks? is false when there are no test cases' do
      expect(commit.fpe_checks?).to be false
    end

    it 'fine_resolution? is false when there are no test cases' do
      expect(commit.fine_resolution?).to be false
    end
  end
end
