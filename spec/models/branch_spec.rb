require 'rails_helper'

RSpec.describe Branch, type: :model do
  # Behaviors specific to this file used to test nearby_test_case_commits'
  # nil-position handling — obsolete now that branch_memberships.position
  # is gone. Coverage of the rewritten nearby_test_case_commits lives in
  # branch_ordering_spec.rb. This file stays as a home for any future
  # general Branch specs.

  describe '.recently_tested' do
    def branch_with_submission(name, at:)
      b = create(:branch, name: name)
      c = create(:commit)
      BranchMembership.create!(branch: b, commit: c)
      b.update!(head: c)
      create(:submission, commit: c, computer: create(:computer)).update_columns(created_at: at)
      b
    end

    it 'orders branches by their most recent submission, skipping stale and excluded ones' do
      old   = branch_with_submission('old', at: 60.days.ago)
      a     = branch_with_submission('a', at: 2.hours.ago)
      b     = branch_with_submission('b', at: 10.minutes.ago)
      c     = branch_with_submission('c', at: 1.day.ago)

      expect(Branch.recently_tested(limit: 3).map { |e| e[:branch] }).to eq([b, a, c])
      expect(Branch.recently_tested(limit: 3, excluding: b).map { |e| e[:branch] }).to eq([a, c])
      expect(Branch.recently_tested(limit: 5).map { |e| e[:branch] }).not_to include(old)
    end
  end
end
