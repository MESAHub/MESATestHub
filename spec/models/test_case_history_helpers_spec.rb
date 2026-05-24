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

  describe '#trend_payload' do
    let(:computer_a) { create(:computer, name: "pleiades") }
    let(:computer_b) { create(:computer, name: "bluebear") }
    let(:computer_c) { create(:computer, name: "vega") }
    let(:computer_d) { create(:computer, name: "cannon") }

    # Build a passing instance with a few interesting scalars set so
    # `trend_extract_value` has something to read.
    def instance_on(tcc:, computer:, threads:, run_optional:, runtime: 1.0, steps: 100)
      submission = create(:submission, commit: tcc.commit, computer: computer)
      create(:test_instance,
             test_case: tcc.test_case,
             test_case_commit: tcc,
             commit: tcc.commit,
             computer: computer,
             submission: submission,
             passed: true,
             success_type: 'run_test_string',
             compiler: 'gfortran',
             omp_num_threads: threads,
             run_optional: run_optional,
             runtime_minutes: runtime,
             steps: steps,
             retries: 2,
             redos: 0,
             solver_iterations: 500,
             solver_calls_made: 200,
             solver_calls_failed: 1)
    end

    def window_entries(branch, tccs_by_commit_id, commits)
      commits.reverse.map do |c|
        tcc = tccs_by_commit_id[c.id]
        { commit: c, tcc: tcc, status: tcc&.status || -1 }
      end
    end

    it 'selects the top-N configs by instance count' do
      commits = chain_on(branch, 5)
      tccs = commits.map { |c| create(:test_case_commit, :passing, commit: c, test_case: test_case) }

      # config A: 4 instances (pleiades · 8t · full)
      # config B: 3 instances (bluebear · 4t · full)
      # config C: 2 instances (vega · 8t · partial)
      # config D: 1 instance  (cannon · 16t · full) — should be excluded at top_n=3
      tccs.first(4).each { |t| instance_on(tcc: t, computer: computer_a, threads: 8,  run_optional: true) }
      tccs.first(3).each { |t| instance_on(tcc: t, computer: computer_b, threads: 4,  run_optional: true) }
      tccs.first(2).each { |t| instance_on(tcc: t, computer: computer_c, threads: 8,  run_optional: false) }
      instance_on(tcc: tccs.first, computer: computer_d, threads: 16, run_optional: true)

      entries = window_entries(branch, tccs.index_by(&:commit_id), commits)
      payload = test_case.trend_payload(branch, entries, top_n: 3)

      expect(payload[:configs].size).to eq(3)
      labels = payload[:configs].map { |c| c[:label] }
      expect(labels[0]).to eq("pleiades · 8t · full")
      expect(labels[1]).to eq("bluebear · 4t · full")
      expect(labels[2]).to eq("vega · 8t · partial")
      # cannon (1 instance) excluded
      expect(payload[:configs].none? { |c| c[:computer] == "cannon" }).to be(true)
    end

    it 'returns commits in chronological order (oldest first) for the X axis' do
      commits = chain_on(branch, 3)
      tccs = commits.map { |c| create(:test_case_commit, :passing, commit: c, test_case: test_case) }
      tccs.each { |t| instance_on(tcc: t, computer: computer_a, threads: 8, run_optional: true) }

      entries = window_entries(branch, tccs.index_by(&:commit_id), commits)
      payload = test_case.trend_payload(branch, entries)

      # commits[] in payload should be in oldest-first order
      expect(payload[:commits].map { |c| c[:sha] }).to eq(commits.map(&:short_sha))
    end

    it 'emits null for (config, commit) pairs with no instance' do
      commits = chain_on(branch, 4)
      tccs = commits.map { |c| create(:test_case_commit, :passing, commit: c, test_case: test_case) }
      # config A submitted on commits 0, 2, 3 only — commit 1 should be a gap
      [0, 2, 3].each { |i| instance_on(tcc: tccs[i], computer: computer_a, threads: 8, run_optional: true, runtime: 1.5) }

      entries = window_entries(branch, tccs.index_by(&:commit_id), commits)
      payload = test_case.trend_payload(branch, entries)
      cfg_key = payload[:configs].first[:key]
      runtime_series = payload[:series]["runtime_minutes"][cfg_key]
      # oldest first: commits[0] = idx 0, commits[1] = idx 1, etc.
      expect(runtime_series[0]).to be_within(0.001).of(1.5)
      expect(runtime_series[1]).to be_nil
      expect(runtime_series[2]).to be_within(0.001).of(1.5)
      expect(runtime_series[3]).to be_within(0.001).of(1.5)
    end

    it 'returns empty configs when the window has no shared instances' do
      commits = chain_on(branch, 3)
      # No TCCs created → no instances
      entries = window_entries(branch, {}, commits)
      payload = test_case.trend_payload(branch, entries)
      expect(payload[:configs]).to be_empty
      expect(payload[:commits].size).to eq(3)
      expect(payload[:metrics]).not_to be_empty   # static spec still listed
    end
  end
end
