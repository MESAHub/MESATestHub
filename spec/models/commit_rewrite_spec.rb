require 'rails_helper'

# Rebases and other force-pushes: corrected_time ordering, pairing a
# dropped commit with its replacement, and BranchSyncJob taking dropped
# commits off the branch. The real case (Nov 2026): EbF/hydro_03 was
# rebased onto main's e669d81 keeping its old committer dates, so the
# commits index put e669d81 above the whole rebased stack.
RSpec.describe CommitRewrite do
  let(:t0) { Time.zone.parse('2026-11-01T00:00:00Z') }

  def commit_at(time, message: 'msg', email: 'eb@example.com', author_time: nil, label: SecureRandom.hex(4))
    sha = Digest::SHA1.hexdigest(label)
    create(:commit, sha: sha, short_sha: sha[0, 7], commit_time: time,
                    message: message, author_email: email, author_time: author_time)
  end

  def link(parent, child)
    CommitRelation.create!(parent: parent, child: child, parent_index: 0)
  end

  describe 'Commit corrected_time' do
    it 'equals commit_time when dates follow the history' do
      a = commit_at(t0)
      b = commit_at(t0 + 1.hour)
      link(a, b)

      expect(b.reload.corrected_time).to eq(b.commit_time)
    end

    it 'puts a rebased stack with old dates above the base it now sits on' do
      main = create(:branch, name: 'main')
      base = commit_at(t0 + 7.hours, label: 'base')
      stack = [commit_at(t0 - 60.days, label: 's1'), commit_at(t0 - 30.days, label: 's2')]
      link(base, stack[0])
      link(stack[0], stack[1])
      main.update!(head: stack[1])

      expect(main.ordered_commits.map(&:id)).to eq([stack[1].id, stack[0].id, base.id])
      expect(stack[0].reload.corrected_time).to eq(base.corrected_time + 1.second)
    end

    it 'orders same-second commits child first' do
      main = create(:branch, name: 'main')
      a = commit_at(t0, label: 'a')
      b = commit_at(t0, label: 'b')
      link(a, b)
      main.update!(head: b)

      expect(main.ordered_commits.map(&:id)).to eq([b.id, a.id])
    end

    it 'raises descendants when a parent arrives after its children' do
      child = commit_at(t0, label: 'child')
      grandchild = commit_at(t0 + 1.second, label: 'grandchild')
      link(child, grandchild)
      parent = commit_at(t0 + 1.day, label: 'parent')

      Commit.ingest_payload_edges(
        [{ sha: child.sha, parents: [{ sha: parent.sha }] }],
        { child.sha => child.id, parent.sha => parent.id }
      )

      expect(child.reload.corrected_time).to eq(parent.corrected_time + 1.second)
      expect(grandchild.reload.corrected_time).to eq(parent.corrected_time + 2.seconds)
    end

    it 'never writes a stale in-memory value back over a correction' do
      a = commit_at(t0 + 1.day, label: 'a')
      b = commit_at(t0, label: 'b')
      stale = Commit.find(b.id)
      link(a, b)

      stale.update!(message: 'edited')
      expect(b.reload.corrected_time).to eq(a.corrected_time + 1.second)
    end
  end

  describe '.pair' do
    it 'pairs by author and message' do
      old = commit_at(t0, message: 'fix x', label: 'old')
      new = commit_at(t0, message: 'fix x', label: 'new')
      other = commit_at(t0, message: 'fix y', label: 'other')

      expect(described_class.pair([old], [new, other])).to eq(old.id => new.id)
    end

    it 'skips a commit with two matches unless author time tells them apart' do
      old = commit_at(t0, message: 'fix', label: 'old')
      n1 = commit_at(t0, message: 'fix', label: 'n1', author_time: t0)
      n2 = commit_at(t0, message: 'fix', label: 'n2', author_time: t0 + 1.hour)
      expect(described_class.pair([old], [n1, n2])).to eq({})

      old.update!(author_time: t0 + 1.hour)
      expect(described_class.pair([old], [n1, n2])).to eq(old.id => n2.id)
    end

    it 'pairs several earlier versions with the current one' do
      v1 = commit_at(t0, message: 'feature', label: 'v1')
      v2 = commit_at(t0, message: 'feature', label: 'v2')
      v3 = commit_at(t0, message: 'feature', label: 'v3')

      expect(described_class.pair([v1, v2], [v3])).to eq(v1.id => v3.id, v2.id => v3.id)
    end
  end

  describe '.predecessors_of' do
    it 'follows a commit rebased more than once, nearest first' do
      branch = create(:branch, name: 'feature')
      v1 = commit_at(t0, label: 'v1')
      v2 = commit_at(t0, label: 'v2')
      v3 = commit_at(t0, label: 'v3')
      described_class.create!(branch: branch, old_commit: v1, new_commit: v2, rewritten_at: t0)
      described_class.create!(branch: branch, old_commit: v2, new_commit: v3, rewritten_at: t0 + 1.day)

      expect(described_class.predecessors_of(v3).map(&:old_commit)).to eq([v2, v1])
    end
  end

  describe 'BranchSyncJob on a force-push' do
    let(:branch) { create(:branch, name: 'feature') }
    let(:client) { double('octokit') }

    def gh(commit_or_sha, parents:, message: 'msg', time: t0)
      sha = commit_or_sha.is_a?(Commit) ? commit_or_sha.sha : commit_or_sha
      { sha: sha,
        commit: { author: { name: 'EB', email: 'eb@example.com', date: t0 - 90.days },
                  committer: { name: 'EB', email: 'eb@example.com', date: time },
                  message: message },
        html_url: "https://github.com/MESAHub/mesa/commit/#{sha}",
        parents: parents.map { |p| { sha: p.is_a?(Commit) ? p.sha : p } } }
    end

    # base <- old1 <- old2 (the branch), and base <- main_tip on main.
    let!(:base) { commit_at(t0 - 10.days, label: 'base') }
    let!(:old1) { commit_at(t0 - 5.days, message: 'one', label: 'old1') }
    let!(:old2) { commit_at(t0 - 4.days, message: 'two', label: 'old2') }
    let!(:main_tip) { commit_at(t0, label: 'main_tip') }

    before do
      link(base, old1)
      link(old1, old2)
      link(base, main_tip)
      branch.update!(head: old2)
      branch.absorb_commits([base.id, old1.id, old2.id])
      allow(Commit).to receive(:api).and_return(client)
      allow(Commit).to receive(:populate_payload_test_cases)
    end

    def push(after, compare)
      allow(client).to receive(:compare).and_return(compare)
      BranchSyncJob.new.perform(
        'ref' => 'refs/heads/feature', 'before' => old2.sha, 'after' => after,
        'created' => false, 'deleted' => false, 'forced' => true, 'commits' => []
      )
    end

    it 'takes the dropped commits off the branch and pairs them with their replacements' do
      new1 = Digest::SHA1.hexdigest('new1')
      new2 = Digest::SHA1.hexdigest('new2')
      # Rebased onto main_tip, keeping committer dates older than it.
      push(new2, { status: 'diverged', total_commits: 3, commits: [
        gh(main_tip, parents: [base], time: t0),
        gh(new1, parents: [main_tip], message: 'one', time: t0 - 5.days),
        gh(new2, parents: [new1], message: 'two', time: t0 - 4.days)
      ] })

      branch.reload
      expect(branch.commits).not_to include(old1, old2)
      expect(branch.ordered_commits.first(3).map(&:sha)).to eq([new2, new1, main_tip.sha])

      rewrites = described_class.where(branch: branch).index_by(&:old_commit_id)
      expect(rewrites[old1.id].new_commit.sha).to eq(new1)
      expect(rewrites[old2.id].new_commit.sha).to eq(new2)
      expect(rewrites[old2.id].before_sha).to eq(old2.sha)
    end

    it 'handles a reset to an ancestor, which compares with no commits' do
      push(old1.sha, { status: 'behind', total_commits: 0, commits: [] })

      expect(branch.reload.head).to eq(old1)
      expect(branch.commits).not_to include(old2)
      expect(described_class.find_by(branch: branch, old_commit: old2).new_commit).to be_nil
    end

    it 'falls back to the backfill when compare truncates the list' do
      expect(BranchBackfillJob).to receive(:perform_now).with(branch.id)
      new1 = Digest::SHA1.hexdigest('new1')
      push(new1, { status: 'diverged', total_commits: 300, commits: [
        gh(new1, parents: [base], message: 'one')
      ] })
    end
  end
end
