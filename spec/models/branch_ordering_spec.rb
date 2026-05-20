require 'rails_helper'

# Specs for the Phase 3.5 ordering helpers on Branch — the recursive-CTE
# Branch#ordered_commits + count, plus the rewritten nearby_commits and
# nearby_test_case_commits that no longer rely on branch_memberships.position.
RSpec.describe Branch, 'ordering and nearby helpers' do
  def commit_with_sha(sha, commit_time: Time.zone.parse('2026-01-01T00:00:00Z'))
    create(:commit, sha: sha, short_sha: sha[0, 7],
                    commit_time: commit_time)
  end

  # Build a linear chain (oldest -> newest in array order). Wires up
  # both commit_relations (parent -> child) and branch_memberships
  # for `branch`. Returns the array.
  def chain_on(branch, n, base_time: Time.zone.parse('2026-01-01T00:00:00Z'),
               label: 'c')
    commits = (0...n).map do |i|
      commit_with_sha(Digest::SHA1.hexdigest("#{label}-#{branch.id}-#{i}"),
                      commit_time: base_time + i.hours)
    end
    commits.each_cons(2) do |parent, child|
      CommitRelation.create!(parent: parent, child: child, parent_index: 0)
    end
    branch.absorb_commits(commits.map(&:id))
    branch.update!(head: commits.last)
    commits
  end

  describe '#ordered_commits' do
    let(:branch) { create(:branch, name: 'main') }

    it 'returns commits reachable from head in commit_time DESC order' do
      commits = chain_on(branch, 5)

      ordered = branch.ordered_commits.to_a
      expect(ordered.size).to eq(5)
      expect(ordered.map(&:id)).to eq(commits.reverse.map(&:id))
    end

    it 'supports Kaminari pagination' do
      chain_on(branch, 12)

      page1 = branch.ordered_commits.page(1).per(5)
      page2 = branch.ordered_commits.page(2).per(5)
      page3 = branch.ordered_commits.page(3).per(5)

      expect(page1.size).to eq(5)
      expect(page2.size).to eq(5)
      expect(page3.size).to eq(2)
      expect((page1 + page2 + page3).map(&:id).uniq.size).to eq(12)
    end

    it 'dedupes commits reachable via multiple merge paths' do
      # Build a diamond:
      #     a
      #    / \
      #   b   c
      #    \ /
      #     d  (merge)
      a = commit_with_sha('a' * 40, commit_time: 1.hour.ago)
      b = commit_with_sha('b' * 40, commit_time: 40.minutes.ago)
      c = commit_with_sha('c' * 40, commit_time: 30.minutes.ago)
      d = commit_with_sha('d' * 40, commit_time: 10.minutes.ago)

      CommitRelation.create!(parent: a, child: b, parent_index: 0)
      CommitRelation.create!(parent: a, child: c, parent_index: 0)
      CommitRelation.create!(parent: b, child: d, parent_index: 0)
      CommitRelation.create!(parent: c, child: d, parent_index: 1)

      branch.update!(head: d)

      ordered = branch.ordered_commits.to_a
      expect(ordered.map(&:id)).to eq([d.id, c.id, b.id, a.id])
    end

    it 'returns an empty relation when head_id is nil' do
      expect(branch.ordered_commits.to_a).to eq([])
    end

    it 'walks through commit_relations, not branch_memberships' do
      # Put a commit in the topology that has no branch membership;
      # it should still appear in ordered_commits because the CTE
      # only consults the head pointer and commit_relations.
      commits = chain_on(branch, 3)
      orphan_member = commit_with_sha('z' * 40,
                                      commit_time: commits.first.commit_time - 1.hour)
      CommitRelation.create!(parent: orphan_member, child: commits.first,
                             parent_index: 0)

      expect(branch.ordered_commits.pluck(:id)).to include(orphan_member.id)
    end
  end

  describe '#reachable_commit_count' do
    let(:branch) { create(:branch, name: 'main') }

    it 'counts commits reachable from head' do
      chain_on(branch, 4)
      expect(branch.reachable_commit_count).to eq(4)
    end

    it 'returns 0 when head_id is nil' do
      expect(branch.reachable_commit_count).to eq(0)
    end
  end

  describe '#nearby_commits' do
    let(:branch) { create(:branch, name: 'main') }

    it 'returns commits around the given one in commit_time order' do
      commits = chain_on(branch, 7)
      target  = commits[3]  # middle

      result = branch.nearby_commits(target, 2)
      # newest first: c5, c4, target(c3), c2, c1
      expect(result.map(&:id)).to eq(
        [commits[5], commits[4], commits[3], commits[2], commits[1]].map(&:id)
      )
    end

    it 'returns just the commit when it is not a member of this branch' do
      outsider = create(:commit)
      expect(branch.nearby_commits(outsider, 2)).to eq([outsider])
    end

    it 'handles boundaries: target at oldest end' do
      commits = chain_on(branch, 5)
      result = branch.nearby_commits(commits.first, 2)
      # newest first: c2, c1, target(c0). Nothing before target.
      expect(result.map(&:id)).to eq([commits[2], commits[1], commits[0]].map(&:id))
    end

    it 'handles boundaries: target at newest end' do
      commits = chain_on(branch, 5)
      result = branch.nearby_commits(commits.last, 2)
      # newest first: target(c4), c3, c2.
      expect(result.map(&:id)).to eq([commits[4], commits[3], commits[2]].map(&:id))
    end
  end

  describe '#nearby_test_case_commits' do
    let(:branch)    { create(:branch, name: 'main') }
    let(:test_case) { create(:test_case, name: 'evolve_zams', module: 'star') }

    it 'returns TCCs around the target in commit_time order' do
      commits = chain_on(branch, 5)
      tccs = commits.map do |c|
        TestCaseCommit.create!(commit: c, test_case: test_case)
      end
      target = tccs[2]

      result = branch.nearby_test_case_commits(target, 1)
      expect(result.map(&:commit_id)).to eq(
        [commits[3], commits[2], commits[1]].map(&:id)
      )
    end

    it 'skips commits that have no TCC for this test case' do
      # Test case is only present on c1 and c3 (not c0, c2, c4)
      commits = chain_on(branch, 5)
      t1 = TestCaseCommit.create!(commit: commits[1], test_case: test_case)
      target = TestCaseCommit.create!(commit: commits[3], test_case: test_case)

      result = branch.nearby_test_case_commits(target, 5)
      expect(result.map(&:commit_id)).to eq([commits[3].id, commits[1].id])
    end

    it 'returns just the TCC when the commit is not a member of this branch' do
      outsider = create(:commit)
      tcc = TestCaseCommit.create!(commit: outsider, test_case: test_case)
      expect(branch.nearby_test_case_commits(tcc)).to eq([tcc])
    end
  end
end
