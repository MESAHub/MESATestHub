require 'rails_helper'

RSpec.describe MorningReport, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  # Wire a complete test instance + submission tree. `created_at` moves
  # both, since the report selects commits by submission time.
  def make_instance(commit:, computer:, test_case:, created_at: nil, **attrs)
    submission = create(:submission, commit: commit, computer: computer)
    ti = create(:test_instance, commit: commit, computer: computer,
                                test_case: test_case, submission: submission,
                                **attrs)
    if created_at
      submission.update_columns(created_at: created_at)
      ti.update_columns(created_at: created_at)
    end
    ti
  end

  def commit_ids(report)
    report.summaries.map { |cs| cs.commit.id }
  end

  # 2026-05-25 is EDT: the digest goes out at 12:00 UTC.
  let(:send_date) { Date.new(2026, 5, 25) }
  let(:as_of) { described_class.send_time(send_date) }
  let(:test_case) { create(:test_case) }
  let(:computer) { create(:computer) }
  let(:main_branch) { create(:branch, name: 'main') }

  describe 'the window' do
    it 'ends at 8:00 AM US Eastern on the send date' do
      expect(as_of).to eq(Time.utc(2026, 5, 25, 12))
      expect(described_class.send_time(Date.new(2026, 12, 1))).to eq(Time.utc(2026, 12, 1, 13))
    end

    it 'returns an empty report when nothing arrived in the window' do
      report = described_class.new(as_of: as_of).build
      expect(report.any_commits?).to be(false)
      expect(report.sections).to be_empty
      expect(report.anomalies).to be_empty
    end

    it 'tiles days: a result just after one send lands in the next day, not the gap' do
      commit = create(:commit)
      create(:branch_membership, branch: main_branch, commit: commit)
      make_instance(commit: commit, computer: computer, test_case: test_case,
                    created_at: as_of + 3.hours)

      today = described_class.new(as_of: as_of).build
      tomorrow = described_class.new(as_of: described_class.send_time(send_date + 1)).build
      expect(commit_ids(today)).to be_empty
      expect(commit_ids(tomorrow)).to eq([commit.id])
    end

    it 'builds a live, uncached report before the send time' do
      travel_to(as_of - 2.hours) do
        commit = create(:commit)
        create(:branch_membership, branch: main_branch, commit: commit)
        make_instance(commit: commit, computer: computer, test_case: test_case)
        report = described_class.for(date: send_date)
        expect(report.window_end).to be_within(1.second).of(Time.current)
        expect(commit_ids(report)).to eq([commit.id])
      end
    end
  end

  describe 'which commits are in it' do
    let(:in_window) { as_of - 2.hours }

    it 'includes a commit whose only report is a failed build' do
      commit = create(:commit)
      create(:branch_membership, branch: main_branch, commit: commit)
      sub = create(:submission, commit: commit, computer: computer,
                                compiled: false, entire: false, empty: true)
      sub.update_columns(created_at: in_window)

      report = described_class.new(as_of: as_of).build
      summary = report.summaries.first
      expect(summary.commit).to eq(commit)
      expect(summary.build_status).to eq(:all_fail)
      expect(summary.failed_build_computers).to eq([computer.name])
      expect(report.attention_summaries).to eq([summary])
    end

    it 'includes a commit with only a claim (testing in progress)' do
      commit = create(:commit)
      create(:branch_membership, branch: main_branch, commit: commit)
      claim = create(:claim, commit: commit, computer: computer)
      claim.update_columns(created_at: in_window)

      expect(commit_ids(described_class.new(as_of: as_of).build)).to eq([commit.id])
    end

    it 'leaves out commits with nothing new in the window' do
      commit = create(:commit)
      create(:branch_membership, branch: main_branch, commit: commit)
      make_instance(commit: commit, computer: computer, test_case: test_case,
                    created_at: as_of - 30.hours)

      expect(described_class.new(as_of: as_of).build.any_commits?).to be(false)
    end
  end

  describe 'sections' do
    let(:in_window) { as_of - 2.hours }

    def tested_commit(*branches, time: Time.current)
      commit = create(:commit, commit_time: time, corrected_time: time)
      branches.each { |b| create(:branch_membership, branch: b, commit: commit) }
      make_instance(commit: commit, computer: computer, test_case: test_case,
                    created_at: in_window)
      commit
    end

    let(:report) { described_class.new(as_of: as_of).build }

    it 'lists each commit once: a commit on main is not repeated under branches that merged it' do
      feature = create(:branch, name: 'feature/foo')
      shared = tested_commit(main_branch, feature)
      own = tested_commit(feature)

      expect(report.sections.map(&:kind)).to eq(%i[main branch])
      expect(report.sections.first.commit_summaries.map(&:commit)).to eq([shared])
      expect(report.sections.last.commit_summaries.map(&:commit)).to eq([own])
      expect(report.summaries.size).to eq(2)
    end

    it 'groups stacked branches into one family, each commit once' do
      base = create(:branch, name: 'stack/01')
      top = create(:branch, name: 'stack/02')
      lone = create(:branch, name: 'other')
      low = tested_commit(base, top, time: 2.days.ago)
      high = tested_commit(top, time: 1.day.ago)
      solo = tested_commit(lone)

      family = report.sections.find { |s| s.kind == :family }
      expect(family.branch_names).to eq(%w[stack/01 stack/02])
      expect(family.commit_summaries.map(&:commit)).to eq([high, low])
      expect(report.sections.map(&:kind)).to eq(%i[family branch])
      expect(report.sections.last.commit_summaries.map(&:commit)).to eq([solo])
    end

    it 'links a commit through main when it is on main' do
      feature = create(:branch, name: 'feature/foo')
      tested_commit(main_branch, feature)
      expect(report.summaries.first.link_branch_name).to eq('main')
    end

    it 'puts branchless commits last, with no link' do
      tested_commit(main_branch)
      tested_commit

      expect(report.sections.map(&:kind)).to eq(%i[main unattached])
      expect(report.sections.last.commit_summaries.first.link_branch_name).to be_nil
    end

    it 'files a force-pushed-away commit under its old branch, not as needing attention' do
      feature = create(:branch, name: 'feature/foo')
      old = create(:commit)
      replacement = tested_commit(feature)
      make_instance(commit: old, computer: computer, test_case: test_case,
                    created_at: in_window, passed: false)
      CommitRewrite.create!(branch: feature, old_commit: old, new_commit: replacement,
                            rewritten_at: in_window)

      section = report.sections.sole
      expect(section.kind).to eq(:branch)
      rewritten = section.rewritten_summaries.sole
      expect(rewritten.commit).to eq(old)
      expect(rewritten.link_branch_name).to eq('feature/foo')
      expect(rewritten.replacement).to eq(replacement)
      expect(rewritten.tests_status).to eq(:fail)
      expect(rewritten.needs_attention?).to be(false)
    end

    it 'counts commits needing attention once, however many branches they are on' do
      a = create(:branch, name: 'a')
      b = create(:branch, name: 'b')
      commit = create(:commit)
      [main_branch, a, b].each { |br| create(:branch_membership, branch: br, commit: commit) }
      make_instance(commit: commit, computer: computer, test_case: test_case,
                    created_at: in_window, passed: false)

      expect(report.attention_summaries.map(&:commit)).to eq([commit])
    end
  end

  describe 'statuses come from CommitState' do
    it 'calls a run with some results and the rest untested :partial, not untested' do
      commit = create(:commit)
      create(:branch_membership, branch: main_branch, commit: commit)
      other_case = create(:test_case, name: 'not_run_yet')
      create(:test_case_commit, commit: commit, test_case: other_case)
      make_instance(commit: commit, computer: computer, test_case: test_case,
                    created_at: as_of - 1.hour)

      summary = described_class.new(as_of: as_of).build.summaries.sole
      expect(summary.tests_status).to eq(:partial)
      expect(summary.needs_attention?).to be(false)
    end
  end

  describe 'FPE-only failures' do
    def summary_for(commit)
      described_class.new.send(:build_summary, commit, commit.commit_state)
    end

    it 'splits them out of failing/mixed and labels them :fpe' do
      commit = create(:commit)
      fpe_case = create(:test_case, name: 'fpe_case')
      real_case = create(:test_case, name: 'real_case')
      make_instance(commit: commit, computer: computer, test_case: fpe_case,
                    passed: false, failure_type: 'fpe', fpe_checks: true)
      make_instance(commit: commit, computer: computer, test_case: real_case,
                    passed: false, failure_type: 'exit_code')

      summary = summary_for(commit.reload)
      fpe_tcc = summary.problem_tccs.find { |t| t.test_case == fpe_case }
      real_tcc = summary.problem_tccs.find { |t| t.test_case == real_case }

      expect(summary.fpe_tccs).to eq([fpe_tcc])
      expect(summary.failing_tccs).to eq([real_tcc])
      expect(summary.label_for(fpe_tcc)).to eq(:fpe)
      expect(summary.label_for(real_tcc)).to eq(:failing)
      expect(summary.problem_tccs).to eq([real_tcc, fpe_tcc])
    end

    it 'counts a likely FPE failure (same computer passed with FPE checks off)' do
      commit = create(:commit)
      tc = create(:test_case, name: 'likely_fpe')
      make_instance(commit: commit, computer: computer, test_case: tc,
                    passed: false, failure_type: 'exit_code', fpe_checks: true)
      make_instance(commit: commit, computer: computer, test_case: tc,
                    passed: true, fpe_checks: false)

      summary = summary_for(commit.reload)
      expect(summary.fpe_tccs.map(&:test_case)).to eq([tc])
      expect(summary.mixed_tccs).to be_empty
    end
  end

  describe 'anomaly detection' do
    let(:cohort_size) { described_class::COHORT_MIN_SIZE + 4 }

    # A stable cohort of passing runs from before the window (runtime in
    # minutes, memory in kB, with a little spread), then fresh results.
    def seed_cohort(runtime:, mem_rn: 1_000_000, count: cohort_size, tc: test_case, **attrs)
      count.times do |i|
        commit = create(:commit, commit_time: as_of - (10 + i).days)
        make_instance(commit: commit, computer: computer, test_case: tc,
                      created_at: as_of - (10 + i).days,
                      runtime_minutes: runtime + (i % 2) * 0.1 * runtime,
                      mem_rn: mem_rn, mem_re: mem_rn / 2, **attrs)
      end
    end

    # One passing run on a fresh commit, in the window by default. Each
    # call lands a minute after the last, so runs keep their order.
    def add_candidate(runtime:, mem_rn: 1_000_000, at: nil, commit: nil, tc: test_case, **overrides)
      @candidate_clock = (@candidate_clock || as_of - 3.hours) + 1.minute
      at ||= @candidate_clock
      commit ||= create(:commit, commit_time: at)
      make_instance(commit: commit, computer: computer, test_case: tc,
                    created_at: at, runtime_minutes: runtime,
                    mem_rn: mem_rn, mem_re: mem_rn / 2, **overrides)
    end

    # Two commits in a row out of range: the shape that gets reported.
    def add_streak(runtime:, **overrides)
      add_candidate(runtime: runtime, **overrides)
      add_candidate(runtime: runtime, **overrides)
    end

    def flagged(candidate)
      described_class.new(as_of: as_of).build.anomalies
                     .select { |a| a.test_instance.id == candidate.id }
    end

    it 'flags runs far slower than their cohort on two commits in a row' do
      seed_cohort(runtime: 10)
      candidate = add_streak(runtime: 40)

      hits = flagged(candidate)
      expect(hits.map(&:metric)).to eq([:runtime])
      expect(hits.first.cohort_size).to eq(cohort_size)
      expect(hits.first.ratio).to be > 3
      expect(hits.first.occurrences).to eq(2)
    end

    it 'leaves out a lone slow run between normal ones' do
      seed_cohort(runtime: 10)
      add_candidate(runtime: 10)
      spike = add_candidate(runtime: 40)
      add_candidate(runtime: 10)
      expect(flagged(spike)).to be_empty
    end

    it 'leaves out a slow commit that a normal rerun of the same commit clears' do
      seed_cohort(runtime: 10)
      first = add_candidate(runtime: 40)
      add_candidate(runtime: 10, commit: first.commit)
      expect(flagged(add_candidate(runtime: 40))).to be_empty
    end

    it 'counts the last run before the window toward the streak' do
      seed_cohort(runtime: 10)
      add_candidate(runtime: 40, at: as_of - 2.days)
      candidate = add_candidate(runtime: 40)
      expect(flagged(candidate).map(&:occurrences)).to eq([2])
    end

    it 'does not repeat a streak an earlier digest already reported' do
      seed_cohort(runtime: 10)
      add_candidate(runtime: 40, at: as_of - 3.days)
      add_candidate(runtime: 40, at: as_of - 2.days)
      expect(flagged(add_candidate(runtime: 40))).to be_empty
    end

    describe 'in branch order' do
      # A commit on `branch`, `minutes` into the branch's history.
      def branch_commit(branch, minutes)
        commit = create(:commit, commit_time: as_of - 1.day + minutes.minutes)
        commit.update_columns(corrected_time: commit.commit_time)
        create(:branch_membership, branch: branch, commit: commit)
        commit
      end

      let(:feature) { create(:branch, name: 'feature') }
      let(:other) { create(:branch, name: 'other') }

      it 'finds a streak tested out of order' do
        seed_cohort(runtime: 10)
        f1, f2, f3 = [1, 2, 3].map { |m| branch_commit(feature, m) }
        add_candidate(runtime: 40, commit: f1)
        add_candidate(runtime: 10, commit: f3)
        later = add_candidate(runtime: 40, commit: f2)

        expect(flagged(later).map(&:occurrences)).to eq([2])
      end

      it 'does not join slow commits on different branches tested back to back' do
        seed_cohort(runtime: 10)
        fa, fb = [1, 3].map { |m| branch_commit(feature, m) }
        oa, ob = [2, 4].map { |m| branch_commit(other, m) }
        add_candidate(runtime: 10, commit: fa, at: as_of - 2.days)
        add_candidate(runtime: 10, commit: oa, at: as_of - 2.days + 1.minute)
        add_candidate(runtime: 40, commit: fb)
        add_candidate(runtime: 40, commit: ob)

        expect(described_class.new(as_of: as_of).build.anomalies).to be_empty
      end
    end

    it 'does not flag runs within normal variance' do
      seed_cohort(runtime: 10)
      expect(flagged(add_streak(runtime: 11))).to be_empty
    end

    it 'does not flag a big ratio on a tiny absolute change' do
      seed_cohort(runtime: 0.2)
      expect(flagged(add_streak(runtime: 0.8))).to be_empty
    end

    it 'does not flag when the cohort is below COHORT_MIN_SIZE' do
      seed_cohort(runtime: 10, count: described_class::COHORT_MIN_SIZE - 1)
      expect(flagged(add_streak(runtime: 999))).to be_empty
    end

    it 'keeps cohorts apart by inlist count, FPE checks and threads' do
      seed_cohort(runtime: 10, inlist_count: 1)
      expect(flagged(add_streak(runtime: 999, inlist_count: 3))).to be_empty
      expect(flagged(add_streak(runtime: 999, inlist_count: 1, fpe_checks: true))).to be_empty
      expect(flagged(add_streak(runtime: 999, inlist_count: 1, omp_num_threads: 64))).to be_empty
    end

    it 'ignores run_optional when the inlist count matches' do
      # Single-inlist tests arrive with the flag both ways.
      seed_cohort(runtime: 10, inlist_count: 1, run_optional: false)
      candidate = add_streak(runtime: 40, inlist_count: 1, run_optional: true)
      expect(flagged(candidate).map(&:metric)).to eq([:runtime])
    end

    it 'falls back to run_optional for rows without an inlist count' do
      seed_cohort(runtime: 10, inlist_count: nil, run_optional: false)
      expect(flagged(add_streak(runtime: 999, inlist_count: nil, run_optional: true))).to be_empty
      expect(flagged(add_streak(runtime: 999, inlist_count: nil, run_optional: false))).not_to be_empty
    end

    it "links through the branch the digest uses for the commit" do
      seed_cohort(runtime: 10)
      candidate = add_streak(runtime: 40)
      create(:branch_membership, branch: main_branch, commit: candidate.commit)

      expect(flagged(candidate).first.link_branch_name).to eq('main')
    end

    it 'flags a memory blowup as :rn_mem' do
      seed_cohort(runtime: 10, mem_rn: 1_000_000)
      candidate = add_streak(runtime: 10, mem_rn: 5_000_000)
      expect(flagged(candidate).map(&:metric)).to include(:rn_mem)
    end

    it 'reports a streak once, at its worst commit, with its length' do
      seed_cohort(runtime: 10)
      add_candidate(runtime: 40)
      add_candidate(runtime: 50)
      add_candidate(runtime: 45)

      anomalies = described_class.new(as_of: as_of).build.anomalies
      expect(anomalies.size).to eq(1)
      expect(anomalies.first.occurrences).to eq(3)
      expect(anomalies.first.value).to eq(50)
    end

    it 'folds one computer running slow on many tests into a machine slowdown' do
      tests = Array.new(described_class::MACHINE_SLOWDOWN_MIN_TESTS) { create(:test_case) }
      tests.each do |tc|
        seed_cohort(runtime: 10, mem_rn: 1_000_000, tc: tc)
        add_streak(runtime: 20, mem_rn: 5_000_000, tc: tc)
      end

      report = described_class.new(as_of: as_of).build
      expect(report.machine_slowdowns.map { |m| [m.computer, m.test_count] })
        .to eq([[computer, tests.size]])
      # Memory doesn't depend on load, so those findings stay.
      expect(report.anomalies.map(&:metric).uniq).to contain_exactly(:rn_mem, :re_mem)
    end

    it 'keeps runtime findings when only a few tests on a computer ran slow' do
      seed_cohort(runtime: 10)
      add_streak(runtime: 40)
      report = described_class.new(as_of: as_of).build
      expect(report.machine_slowdowns).to be_empty
      expect(report.anomalies.map(&:metric)).to eq([:runtime])
    end
  end
end
