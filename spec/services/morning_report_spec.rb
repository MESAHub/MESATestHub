require 'rails_helper'

RSpec.describe MorningReport, type: :model do
  # Helper to wire a complete test instance + submission tree, since the
  # `belongs_to :submission` validation on TestInstance won't accept a
  # bare factory(:test_instance) without a submission_id. `created_at`
  # can be overridden so we don't have to fiddle with global Time.
  def make_instance(commit:, computer:, test_case:, created_at: nil, **attrs)
    submission = create(:submission, commit: commit, computer: computer)
    ti = create(:test_instance, commit: commit, computer: computer,
                                test_case: test_case, submission: submission,
                                **attrs)
    ti.update_columns(created_at: created_at) if created_at
    ti
  end

  describe '.for' do
    let(:as_of) { Time.zone.local(2026, 5, 25, 8, 0, 0) }

    it 'returns an empty report when no test instances exist in the window' do
      report = described_class.new(as_of: as_of).build
      expect(report.any_commits?).to be(false)
      expect(report.branch_sections).to be_empty
      expect(report.anomalies).to be_empty
    end

    context 'with commits tested across two branches' do
      let(:main_branch)    { create(:branch, name: 'main') }
      let(:feature_branch) { create(:branch, name: 'feature/foo') }
      let(:test_case)      { create(:test_case) }
      let(:computer)       { create(:computer) }
      let(:in_window_time) { as_of - 2.hours }
      let(:out_of_window_time) { as_of - 30.hours }

      let(:main_commit) do
        create(:commit, commit_time: in_window_time - 1.minute)
      end
      let(:feature_commit) do
        create(:commit, commit_time: in_window_time - 5.minutes)
      end
      let(:stale_commit) do
        create(:commit, commit_time: out_of_window_time)
      end

      before do
        create(:branch_membership, branch: main_branch, commit: main_commit)
        create(:branch_membership, branch: feature_branch,
                                   commit: feature_commit)
        create(:branch_membership, branch: main_branch, commit: stale_commit)

        make_instance(commit: main_commit, computer: computer,
                      test_case: test_case, created_at: in_window_time)
        make_instance(commit: feature_commit, computer: computer,
                      test_case: test_case, created_at: in_window_time)
        make_instance(commit: stale_commit, computer: computer,
                      test_case: test_case, created_at: out_of_window_time)
      end

      it 'puts the main branch first, even if the feature commit is newer' do
        report = described_class.new(as_of: as_of).build
        names = report.branch_sections.map { |s| s.branch.name }
        expect(names).to eq(['main', 'feature/foo'])
      end

      it 'only includes commits whose test instances landed in-window' do
        report = described_class.new(as_of: as_of).build
        all_commit_ids = report.branch_sections.flat_map { |s|
          s.commit_summaries.map { |cs| cs.commit.id }
        }
        expect(all_commit_ids).to contain_exactly(main_commit.id,
                                                   feature_commit.id)
      end
    end
  end

  describe 'anomaly detection' do
    let(:as_of)     { Time.zone.local(2026, 5, 25, 8, 0, 0) }
    let(:test_case) { create(:test_case) }
    let(:computer)  { create(:computer) }
    let(:cohort_size) { described_class::COHORT_MIN_SIZE + 4 }

    # Build a stable cohort of historical passing instances, then evaluate
    # the report against one fresh in-window candidate.
    def seed_cohort(runtime:, mem_rn: 1_000_000, count: cohort_size)
      count.times do |i|
        commit = create(:commit, commit_time: as_of - (10 + i).days)
        make_instance(commit: commit, computer: computer, test_case: test_case,
                      created_at: as_of - (10 + i).days,
                      runtime_seconds: runtime, re_time: runtime / 4,
                      total_runtime_seconds: runtime + runtime / 4,
                      mem_rn: mem_rn, mem_re: mem_rn / 2)
      end
    end

    def add_candidate(runtime:, mem_rn: 1_000_000, **overrides)
      commit = create(:commit, commit_time: as_of - 1.hour)
      make_instance(commit: commit, computer: computer, test_case: test_case,
                    created_at: as_of - 1.hour,
                    runtime_seconds: runtime, re_time: runtime / 4,
                    total_runtime_seconds: runtime + runtime / 4,
                    mem_rn: mem_rn, mem_re: mem_rn / 2, **overrides)
    end

    it 'flags a candidate whose runtime is far above the cohort mean' do
      seed_cohort(runtime: 100)
      candidate = add_candidate(runtime: 1_000)

      report = described_class.new(as_of: as_of).build
      flagged = report.anomalies.select do |a|
        a.test_instance.id == candidate.id && a.metric == :rn_runtime
      end
      expect(flagged.size).to eq(1)
      expect(flagged.first.z_score).to be > described_class::ANOMALY_Z_THRESHOLD
      expect(flagged.first.cohort_size).to eq(cohort_size)
    end

    it 'does NOT flag a candidate within normal cohort variance' do
      seed_cohort(runtime: 100)
      candidate = add_candidate(runtime: 105)

      report = described_class.new(as_of: as_of).build
      flagged = report.anomalies.select do |a|
        a.test_instance.id == candidate.id
      end
      expect(flagged).to be_empty
    end

    it 'does NOT flag when the cohort is below COHORT_MIN_SIZE' do
      seed_cohort(runtime: 100, count: described_class::COHORT_MIN_SIZE - 1)
      candidate = add_candidate(runtime: 9_999)

      report = described_class.new(as_of: as_of).build
      flagged = report.anomalies.select do |a|
        a.test_instance.id == candidate.id
      end
      expect(flagged).to be_empty
    end

    it 'isolates cohorts by run_optional / fpe_checks' do
      seed_cohort(runtime: 100)
      # Candidate is on a DIFFERENT cohort (run_optional=true), and we
      # haven't seeded a run_optional=true cohort. With no cohort, no
      # anomaly should fire — confirming the partition.
      candidate = add_candidate(runtime: 9_999, run_optional: true)

      report = described_class.new(as_of: as_of).build
      flagged = report.anomalies.select do |a|
        a.test_instance.id == candidate.id
      end
      expect(flagged).to be_empty
    end

    it 'flags a memory blowup as a separate anomaly with metric :rn_mem' do
      seed_cohort(runtime: 100, mem_rn: 1_000_000)
      candidate = add_candidate(runtime: 105, mem_rn: 50_000_000)

      report = described_class.new(as_of: as_of).build
      flagged = report.anomalies.select do |a|
        a.test_instance.id == candidate.id
      end
      expect(flagged.map(&:metric)).to include(:rn_mem)
    end
  end
end
