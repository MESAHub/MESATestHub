require 'rails_helper'

# These specs exercise Branch.api_update_branches against the real DB, but
# stub the outbound GitHub calls. They focus on the deletion path — branches
# that exist locally but no longer exist on GitHub.
RSpec.describe Branch, '.api_update_branches', type: :model do
  # Sawyer::Resource gives both hash-style ([:foo]) and method-style (.foo)
  # access. This tiny stand-in does the same for our purposes.
  class FakeApiResource
    def initialize(data)
      @data = data.deep_symbolize_keys
    end

    def [](key)
      val = @data[key.to_sym]
      val.is_a?(Hash) ? FakeApiResource.new(val) : val
    end

    def name = @data[:name]
    def commit = FakeApiResource.new(@data[:commit])
    def sha = @data[:sha]
  end

  let(:head_sha) { 'a' * 40 }

  let(:keep_branch) do
    branch = create(:branch, name: 'keeper')
    commit = create(:commit, sha: head_sha, short_sha: head_sha[0, 7])
    BranchMembership.create!(branch: branch, commit: commit, position: 1)
    branch.update!(head: commit)
    branch
  end

  let(:doomed_branch) do
    branch = create(:branch, name: 'doomed')
    commit = create(:commit)
    BranchMembership.create!(branch: branch, commit: commit, position: 1)
    branch.update!(head: commit)
    branch
  end

  before do
    keep_branch
    doomed_branch
    # Pretend GitHub still has `keeper` (with the same head SHA so the
    # per-branch api_update is skipped) and that `doomed` has been deleted.
    allow(Branch).to receive(:api_branches).and_return(
      [FakeApiResource.new(name: 'keeper', commit: { sha: head_sha })]
    )
  end

  it 'deletes branches that no longer exist on GitHub' do
    expect { Branch.api_update_branches }
      .to change { Branch.exists?(name: 'doomed') }.from(true).to(false)
  end

  it 'deletes the memberships of the deleted branch' do
    doomed_id = doomed_branch.id
    expect { Branch.api_update_branches }
      .to change { BranchMembership.where(branch_id: doomed_id).count }
      .from(1).to(0)
  end

  it 'leaves the kept branch and its memberships intact' do
    Branch.api_update_branches

    expect(Branch.find_by(name: 'keeper')).to eq(keep_branch)
    expect(keep_branch.branch_memberships.count).to eq(1)
  end

  it 'does not delete commits that lived in the deleted branch' do
    # Orphaned commits stay; the comment in api_update_branches says they get
    # cleaned up by a separate weekly task.
    doomed_commit_sha = doomed_branch.commits.first.sha
    Branch.api_update_branches
    expect(Commit.exists?(sha: doomed_commit_sha)).to be true
  end

  context 'with multiple deletions and shared commits' do
    let(:shared_commit) { create(:commit, sha: 's' * 40, short_sha: 'sssssss') }
    let(:second_doomed) do
      branch = create(:branch, name: 'doomed-2')
      BranchMembership.create!(branch: branch, commit: shared_commit, position: 1)
      branch.update!(head: shared_commit)
      branch
    end

    before do
      second_doomed
      # Also attach shared_commit to the doomed_branch — when both are deleted,
      # the commit becomes a true orphan, which exercises the
      # "leave commits alone" guarantee.
      BranchMembership.create!(branch: doomed_branch, commit: shared_commit,
                               position: 2)
    end

    it 'deletes both vanished branches and all their memberships' do
      Branch.api_update_branches

      expect(Branch.exists?(name: 'doomed')).to be false
      expect(Branch.exists?(name: 'doomed-2')).to be false
      expect(BranchMembership.where(branch_id: [doomed_branch.id,
                                                second_doomed.id]))
        .to be_empty
    end

    it 'leaves the shared commit in place even after both owning branches are gone' do
      Branch.api_update_branches
      expect(Commit.exists?(sha: shared_commit.sha)).to be true
    end
  end

  context 'with a doomed branch that has no head_id' do
    before do
      # Simulate a partially-synced branch: rows exist but the head was never
      # assigned (e.g., an api_update that crashed mid-flow).
      doomed_branch.update_column(:head_id, nil)
    end

    it 'still deletes the branch without raising' do
      expect { Branch.api_update_branches }.not_to raise_error
      expect(Branch.exists?(name: 'doomed')).to be false
    end
  end
end
