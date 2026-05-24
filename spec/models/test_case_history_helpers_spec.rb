require 'rails_helper'

# Specs for the branch-scoped helpers added to TestCase for the
# modern test_cases#show page:
#
#   #status_summary_for(branch)
#   #commit_window(branch, anchor_commit:, size:)
#
# Tested against a small linear chain on a single branch, with a
# sibling branch carrying its own commits to verify scoping.
RSpec.describe TestCase, 'branch-scoped history helpers' do
  def commit_with_sha(sha, commit_time: Time.zone.parse('2026-01-01T00:00:00Z'))
    create(:commit, sha: sha, short_sha: sha[0, 7], commit_time: commit_time)
  end

  def chain_on(branch, n, base_time: Time.zone.parse('2026-01-01T00:00:00Z'),
               label: 'h')
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

  let(:branch) { create(:branch, name: 'main') }
  let(:other)  { create(:branch, name: 'feature') }
  let(:test_case) { create(:test_case, name: 'black_hole', module: 'star') }

  describe '#status_summary_for' do
    it 'tallies TCC statuses on the branch and ignores other branches' do
      commits = chain_on(branch, 4)
      other_commits = chain_on(other, 2, label: 'o',
                               base_time: Time.zone.parse('2026-02-01T00:00:00Z'))

      create(:test_case_commit, :passing, commit: commits[0], test_case: test_case)
      create(:test_case_commit, :passing, commit: commits[1], test_case: test_case)
      create(:test_case_commit, :failing, commit: commits[2], test_case: test_case)
      create(:test_case_commit, :mixed,   commit: commits[3], test_case: test_case)
      # noise on the sibling branch — must not leak into main's summary
      create(:test_case_commit, :failing, commit: other_commits[0], test_case: test_case)

      summary = test_case.status_summary_for(branch)
      expect(summary[:counts]).to include(
        passing: 2, failing: 1, mixed: 1, checksum: 0, untested: 0, total: 4
      )
    end

    it 'picks the most recent TCC by commit_time as last_run' do
      commits = chain_on(branch, 3)
      create(:test_case_commit, :passing, commit: commits[0], test_case: test_case)
      create(:test_case_commit, :failing, commit: commits[1], test_case: test_case)
      newest = create(:test_case_commit, :passing, commit: commits[2], test_case: test_case)

      summary = test_case.status_summary_for(branch)
      expect(summary[:last_run]&.id).to eq(newest.id)
      expect(summary[:last_passing]&.id).to eq(newest.id)
      expect(summary[:headline_word]).to eq('passing')
    end

    it 'returns "never run" headline when no TCCs exist on the branch' do
      chain_on(branch, 2)
      summary = test_case.status_summary_for(branch)
      expect(summary[:counts][:total]).to eq(0)
      expect(summary[:last_run]).to be_nil
      expect(summary[:headline_word]).to eq('never run')
    end

    it 'ignores untested TCCs when picking last_run' do
      commits = chain_on(branch, 3)
      tested = create(:test_case_commit, :passing, commit: commits[0], test_case: test_case)
      # commits[1] and commits[2] have TCCs but no submissions — status=-1
      create(:test_case_commit, commit: commits[1], test_case: test_case)
      pending = create(:test_case_commit, commit: commits[2], test_case: test_case)

      summary = test_case.status_summary_for(branch)
      expect(summary[:last_run]&.id).to eq(tested.id)
      expect(summary[:pending_on_head]&.id).to eq(pending.id)
      expect(summary[:headline_word]).to eq('passing')
      expect(summary[:counts][:untested]).to eq(2)
    end
  end

  describe '#commit_window' do
    it 'returns a focused window of entries newest-first around the anchor' do
      commits = chain_on(branch, 7)
      # only some commits have TCCs — the rest render as untested
      tcc_mid  = create(:test_case_commit, :failing, commit: commits[3], test_case: test_case)
      tcc_head = create(:test_case_commit, :passing, commit: commits[6], test_case: test_case)

      window = test_case.commit_window(branch, anchor_commit: commits[3], size: 50)
      expect(window[:size]).to eq(50)
      expect(window[:anchor_commit].id).to eq(commits[3].id)
      expect(window[:at_head]).to be(false)
      # 7 commits total fit comfortably; newest-first
      expect(window[:entries].map { |e| e[:commit].id }).to eq(commits.reverse.map(&:id))
      anchor_entry = window[:entries].find { |e| e[:commit].id == commits[3].id }
      expect(anchor_entry[:tcc]&.id).to eq(tcc_mid.id)
      head_entry = window[:entries].find { |e| e[:commit].id == commits[6].id }
      expect(head_entry[:tcc]&.id).to eq(tcc_head.id)
    end

    it 'flags at_head when the anchor is the branch head' do
      commits = chain_on(branch, 3)
      window = test_case.commit_window(branch, anchor_commit: commits.last, size: 50)
      expect(window[:at_head]).to be(true)
    end

    it 'computes half-window pan targets and nil at branch ends' do
      commits = chain_on(branch, 10)
      # anchor near the newest end so there's room to pan older but
      # nothing newer
      window = test_case.commit_window(branch, anchor_commit: commits.last, size: 50)
      # at HEAD there is no "newer" commit
      expect(window[:newer_anchor_sha]).to be_nil
      # older pan target should be (size/2 = 25, capped at branch
      # length) commits behind the anchor — here, the oldest commit
      expect(window[:older_anchor_sha]).to eq(commits.first.short_sha)

      # interior anchor: both targets non-nil
      mid = commits[5]
      window2 = test_case.commit_window(branch, anchor_commit: mid, size: 50)
      expect(window2[:newer_anchor_sha]).to eq(commits.last.short_sha)
      expect(window2[:older_anchor_sha]).to eq(commits.first.short_sha)
    end

    it 'coerces unknown window sizes back to the default' do
      commits = chain_on(branch, 3)
      window = test_case.commit_window(branch, anchor_commit: commits.last, size: 7)
      expect(window[:size]).to eq(TestCase::DEFAULT_WINDOW_SIZE)
    end

    it 'returns an empty window when anchor_commit is nil' do
      window = test_case.commit_window(branch, anchor_commit: nil, size: 50)
      expect(window[:entries]).to eq([])
      expect(window[:older_anchor_sha]).to be_nil
      expect(window[:newer_anchor_sha]).to be_nil
    end
  end
end
