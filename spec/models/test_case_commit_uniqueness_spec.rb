require 'rails_helper'

# e87d3be (2026-09-24) got two TestCaseCommits per test when two sync
# jobs populated it at once; the matrix then read the empty copy.
RSpec.describe 'TestCaseCommit uniqueness' do
  let(:parent) { create(:commit) }
  let(:child) { create(:commit) }
  let!(:test_cases) { create_list(:test_case, 3) }

  before do
    test_cases.each { |tc| TestCaseCommit.create!(commit: parent, test_case: tc) }
    CommitRelation.create!(parent: parent, child: child)
  end

  it 'refuses a second TCC for the same commit and test at the database level' do
    TestCaseCommit.create!(commit: child, test_case: test_cases.first)
    expect { TestCaseCommit.create!(commit: child, test_case: test_cases.first) }
      .to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "doesn't duplicate when a parent copy overlaps rows another job already inserted" do
    # Simulate the race: another job inserted one row between this
    # job's existence check and its insert.
    allow(child).to receive(:test_case_commits).and_wrap_original do |orig, *args|
      rel = orig.call(*args)
      allow(rel).to receive(:pluck).with(:test_case_id).and_return([])
      rel
    end
    TestCaseCommit.create!(commit: child, test_case: test_cases.first)

    Commit.copy_test_cases_from_parent(child)

    expect(TestCaseCommit.where(commit: child).count).to eq(3)
  end

  it 'reuses an existing TCC when a submission attaches an instance' do
    existing = TestCaseCommit.create!(commit: child, test_case: test_cases.first)
    ti = create(:test_instance, commit: child, test_case: test_cases.first,
                                submission: create(:submission, commit: child))
    expect(ti.test_case_commit_id).to eq(existing.id)
    expect(TestCaseCommit.where(commit: child, test_case: test_cases.first).count).to eq(1)
  end
end

RSpec.describe Submission, '.of_type' do
  it "counts singleton submissions with a NULL entire flag as individual" do
    commit = create(:commit)
    singleton = create(:submission, commit: commit, empty: false, entire: nil)
    build_only = create(:submission, commit: commit, empty: true, entire: false)
    expect(Submission.of_type('individual')).to include(singleton)
    expect(Submission.of_type('individual')).not_to include(build_only)
  end
end
