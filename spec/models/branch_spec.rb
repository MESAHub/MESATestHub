require 'rails_helper'

RSpec.describe Branch, type: :model do
  describe '#nearby_test_case_commits' do
    let(:branch) { create(:branch, name: 'main') }
    let(:test_case) { create(:test_case, name: 'tc', module: 'star') }

    it 'returns just the seed TCC when the membership has a nil position' do
      # Regression: memberships from before the position back-fill have
      # position == nil; (position + 1) and (0...position) raised and broke
      # the test_case_commits#show page.
      commit = create(:commit)
      BranchMembership.create!(branch: branch, commit: commit, position: nil)
      tcc = TestCaseCommit.create!(commit: commit, test_case: test_case)

      result = branch.nearby_test_case_commits(tcc)
      expect(result).to eq([tcc])
    end

    it 'returns just the seed TCC when the commit is not a member of the branch' do
      commit = create(:commit)
      tcc = TestCaseCommit.create!(commit: commit, test_case: test_case)

      result = branch.nearby_test_case_commits(tcc)
      expect(result).to eq([tcc])
    end
  end
end
