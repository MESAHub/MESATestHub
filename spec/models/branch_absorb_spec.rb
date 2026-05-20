require 'rails_helper'

# Specs for the Phase 3.5 membership-update helpers on Branch.
# BranchSyncJob calls these after Commit.ingest_payload_{commits,edges}
# have written the commit and topology rows.
RSpec.describe Branch, 'membership absorption' do
  let(:branch) { create(:branch, name: 'main') }

  def commit_with_sha(sha)
    create(:commit, sha: sha, short_sha: sha[0, 7])
  end

  # Chain helper: builds an array of commits with parent_index=0 edges
  # between consecutive entries. commits[0] is OLDEST. Returns the array
  # in OLDEST-first order so the caller can index naturally.
  def linear_chain(n, label:)
    commits = (0...n).map do |i|
      commit_with_sha(Digest::SHA1.hexdigest("#{label}-#{i}"))
    end
    commits.each_cons(2) do |parent, child|
      CommitRelation.create!(parent: parent, child: child, parent_index: 0)
    end
    commits
  end

  describe '#absorb_commits' do
    it 'inserts (branch, commit) memberships for every id' do
      ids = 3.times.map { create(:commit).id }

      expect { branch.absorb_commits(ids) }
        .to change(BranchMembership, :count).by(3)

      expect(branch.commits.pluck(:id)).to match_array(ids)
    end

    it 'is idempotent: rerunning does not create duplicates' do
      ids = 3.times.map { create(:commit).id }
      branch.absorb_commits(ids)

      expect { branch.absorb_commits(ids) }
        .not_to change(BranchMembership, :count)
    end

    it 'is a no-op for an empty list' do
      expect { branch.absorb_commits([]) }
        .not_to change(BranchMembership, :count)
    end
  end

  describe '#absorb_merge' do
    it 'adds memberships for every commit reachable from the foreign parent' do
      # feature chain: f0 -> f1 -> f2 -> f3 (foreign parent)
      feature = linear_chain(4, label: 'feature')

      # None of the feature commits are in this branch yet.
      expect { branch.absorb_merge([feature.last.id]) }
        .to change(BranchMembership, :count).by(4)

      expect(branch.commits).to match_array(feature)
    end

    it 'stops walking at commits already in the branch (shared ancestors)' do
      # Side branch (s0 -> s1 -> s2 -> s3) shares its base with main:
      # s0 is already in `main`. The merge brings in s1, s2, s3 only.
      side = linear_chain(4, label: 'side')

      # Pre-attach s0 to main (it's the shared base).
      branch.absorb_commits([side[0].id])

      expect { branch.absorb_merge([side.last.id]) }
        .to change(BranchMembership, :count).by(3)

      expect(branch.commits).to match_array(side)
    end

    it 'is idempotent on rerun' do
      feature = linear_chain(3, label: 'idem')

      branch.absorb_merge([feature.last.id])

      expect { branch.absorb_merge([feature.last.id]) }
        .not_to change(BranchMembership, :count)
    end

    it 'is a no-op for an empty list' do
      expect { branch.absorb_merge([]) }
        .not_to change(BranchMembership, :count)
    end

    it 'handles octopus merges (multiple foreign parents)' do
      first  = linear_chain(2, label: 'octo-1')  # 2 commits
      second = linear_chain(3, label: 'octo-2')  # 3 commits

      expect { branch.absorb_merge([first.last.id, second.last.id]) }
        .to change(BranchMembership, :count).by(5)
    end

    it 'dedupes when two foreign parents share an ancestor' do
      # Build a small diamond:
      #     A
      #    / \
      #   B   C
      #    \ /
      #     M (foreign merge that's the tip of side branch)
      a = create(:commit)
      b = create(:commit)
      c = create(:commit)
      m = create(:commit)
      CommitRelation.create!(parent: a, child: b, parent_index: 0)
      CommitRelation.create!(parent: a, child: c, parent_index: 0)
      CommitRelation.create!(parent: b, child: m, parent_index: 0)
      CommitRelation.create!(parent: c, child: m, parent_index: 1)

      # Walking from M's parents [B, C] should reach A exactly once.
      expect { branch.absorb_merge([b.id, c.id]) }
        .to change(BranchMembership, :count).by(3)  # A, B, C
    end

    it 'does not descend past commits already in the branch when their ancestors are not in the branch' do
      # Setup: x_old -> x_mid -> x_tip
      #   We pre-attach x_mid to the branch but NOT x_old.
      #   absorb_merge from x_tip should add x_tip only — x_mid is
      #   already in the branch, so we stop, and don't add x_old
      #   even though x_old is not technically in the branch yet.
      #
      #   That's the invariant the "stop at branch member" optimization
      #   trades on: if a commit is in the branch, by induction so are
      #   its ancestors. If that invariant is broken (e.g., because
      #   memberships were hand-edited), the walk would miss them.
      x_old, x_mid, x_tip = linear_chain(3, label: 'stop-invariant')
      branch.absorb_commits([x_mid.id])

      expect { branch.absorb_merge([x_tip.id]) }
        .to change(BranchMembership, :count).by(1)

      expect(branch.commits).to include(x_mid, x_tip)
      expect(branch.commits).not_to include(x_old)
    end
  end
end
