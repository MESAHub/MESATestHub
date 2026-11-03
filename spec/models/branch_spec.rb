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

  describe '.recently_pushed' do
    def pushed(branch, at:, time: at)
      c = create(:commit, commit_time: time)
      c.update_columns(created_at: at)
      BranchMembership.create!(branch: branch, commit: c)
      branch.update!(head: c)
      c
    end

    let!(:main) { create(:branch, name: 'main') }

    it 'orders branches by latest push and commits by commit_time' do
      feature = create(:branch, name: 'feature')
      newer_time = pushed(feature, at: 3.hours.ago, time: 1.day.ago)
      older_time = pushed(feature, at: 2.hours.ago, time: 2.days.ago)
      on_main = pushed(main, at: 5.hours.ago)
      pushed(create(:branch, name: 'stale'), at: 20.days.ago)

      sections = Branch.recently_pushed(within: 10.days)

      expect(sections.map { |s| s[:branch] }).to eq([feature, main])
      expect(sections.first[:commit_ids]).to eq([newer_time.id, older_time.id])
      expect(sections.first[:last_pushed_at]).to be_within(1.second).of(2.hours.ago)
      expect(sections.last[:commit_ids]).to eq([on_main.id])
    end

    it "leaves main's commits out of other branches and skips excluded branches" do
      shared = pushed(main, at: 1.hour.ago)
      feature = create(:branch, name: 'feature')
      BranchMembership.create!(branch: feature, commit: shared)
      own = pushed(feature, at: 2.hours.ago)
      merged_main_only = create(:branch, name: 'synced')
      BranchMembership.create!(branch: merged_main_only, commit: shared)
      pushed(create(:branch, name: 'shields'), at: 1.hour.ago)

      sections = Branch.recently_pushed(within: 10.days).to_h { |s| [s[:branch].name, s[:commit_ids]] }

      expect(sections).to eq('main' => [shared.id], 'feature' => [own.id])
    end
  end
end
