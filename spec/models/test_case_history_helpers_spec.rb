require 'rails_helper'

# Specs for the branch-scoped helpers added to TestCase for the
# modern test_cases#show page:
#
#   #status_summary_for(branch)
#   #passage_strip_window(branch, limit:)
#   #history_window(branch, page:, per:)
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

  describe '#passage_strip_window' do
    it 'returns commits newest-first with nil tcc for untested commits' do
      commits = chain_on(branch, 4)
      # only the two most recent commits have a TCC for this test
      tcc_a = create(:test_case_commit, :passing, commit: commits[3], test_case: test_case)
      tcc_b = create(:test_case_commit, :failing, commit: commits[2], test_case: test_case)

      entries = test_case.passage_strip_window(branch, limit: 10)
      expect(entries.map { |e| e[:commit].id }).to eq(commits.reverse.map(&:id))
      expect(entries[0][:tcc]&.id).to eq(tcc_a.id)
      expect(entries[1][:tcc]&.id).to eq(tcc_b.id)
      expect(entries[2][:tcc]).to be_nil
      expect(entries[3][:tcc]).to be_nil
      expect(entries[2][:status]).to eq(-1)
    end

    it 'honors the limit' do
      chain_on(branch, 5)
      expect(test_case.passage_strip_window(branch, limit: 3).size).to eq(3)
    end

    it 'returns [] on an empty branch' do
      expect(test_case.passage_strip_window(branch)).to eq([])
    end
  end

  describe '#history_window' do
    it 'paginates TCCs newest first on the branch only' do
      commits = chain_on(branch, 6)
      other_commits = chain_on(other, 2, label: 'o',
                               base_time: Time.zone.parse('2026-02-01T00:00:00Z'))

      commits.each { |c| create(:test_case_commit, :passing, commit: c, test_case: test_case) }
      create(:test_case_commit, :failing, commit: other_commits[0], test_case: test_case)

      page1 = test_case.history_window(branch, page: 1, per: 4)
      page2 = test_case.history_window(branch, page: 2, per: 4)

      expect(page1.size).to eq(4)
      expect(page2.size).to eq(2)
      # newest first
      expect(page1.first.commit_id).to eq(commits.last.id)
      # the sibling branch's failing TCC is not present anywhere in the
      # paginated results
      all_returned = (page1.to_a + page2.to_a)
      expect(all_returned.map(&:commit_id)).not_to include(other_commits[0].id)
    end
  end
end
