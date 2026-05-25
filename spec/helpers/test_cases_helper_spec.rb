require 'rails_helper'

# Helper-level specs for the few TestCasesHelper methods that are
# pure data transforms (and so can be tested cheaply in isolation).
# Stimulus-facing payload builders (history_popover_data,
# history_matrix_payload) are tested implicitly through page-render
# specs; the trickier branch-scoped helpers live in
# spec/models/test_case_history_helpers_spec.rb.
RSpec.describe TestCasesHelper, type: :helper do
  def commit_with_sha(sha, commit_time: Time.zone.parse('2026-01-01T00:00:00Z'))
    create(:commit, sha: sha, short_sha: sha[0, 7], commit_time: commit_time)
  end

  let(:test_case) { create(:test_case, name: 'black_hole', module: 'star') }
  let(:computer_a) { create(:computer, name: "pleiades") }
  let(:computer_b) { create(:computer, name: "bluebear") }

  def make_entry(commit, tcc)
    { commit: commit, tcc: tcc, status: tcc&.status || -1 }
  end

  def instance_on(tcc:, computer:, runtime: 1.0)
    submission = create(:submission, commit: tcc.commit, computer: computer)
    create(:test_instance,
           test_case: tcc.test_case, test_case_commit: tcc,
           commit: tcc.commit, computer: computer, submission: submission,
           passed: true, success_type: 'run_test_string', compiler: 'gfortran',
           omp_num_threads: 8, run_optional: true,
           runtime_minutes: runtime, steps: 100, retries: 0, redos: 0)
  end

  describe '#submissions_payload' do
    it 'defaults to the most-active computer when chosen_name is nil' do
      c1 = commit_with_sha('a' * 40, commit_time: 2.days.ago)
      c2 = commit_with_sha('b' * 40, commit_time: 1.day.ago)
      tcc1 = create(:test_case_commit, :passing, commit: c1, test_case: test_case)
      tcc2 = create(:test_case_commit, :passing, commit: c2, test_case: test_case)

      # bluebear: 2 instances, pleiades: 1 — bluebear should win.
      instance_on(tcc: tcc1, computer: computer_b)
      instance_on(tcc: tcc2, computer: computer_b)
      instance_on(tcc: tcc1, computer: computer_a)

      entries = [make_entry(c2, tcc2), make_entry(c1, tcc1)]
      payload = helper.submissions_payload(entries)
      expect(payload[:chosen]).to eq(computer_b)
      expect(payload[:options].map { |o| o[:name] }).to eq(%w[bluebear pleiades])
      expect(payload[:options].first[:count]).to eq(2)
      expect(payload[:instances].size).to eq(2)
    end

    it 'honors chosen_name when it appears in the options' do
      c1 = commit_with_sha('a' * 40, commit_time: 1.day.ago)
      tcc1 = create(:test_case_commit, :passing, commit: c1, test_case: test_case)
      instance_on(tcc: tcc1, computer: computer_a)
      instance_on(tcc: tcc1, computer: computer_b)

      payload = helper.submissions_payload([make_entry(c1, tcc1)], chosen_name: "pleiades")
      expect(payload[:chosen]).to eq(computer_a)
      expect(payload[:instances].size).to eq(1)
      expect(payload[:instances].first.computer).to eq(computer_a)
    end

    it 'returns chosen: nil when the named computer is not in the window' do
      c1 = commit_with_sha('a' * 40, commit_time: 1.day.ago)
      tcc1 = create(:test_case_commit, :passing, commit: c1, test_case: test_case)
      instance_on(tcc: tcc1, computer: computer_a)

      payload = helper.submissions_payload([make_entry(c1, tcc1)], chosen_name: "ghost")
      expect(payload[:chosen]).to be_nil
      expect(payload[:instances]).to be_empty
      expect(payload[:options].map { |o| o[:name] }).to eq(%w[pleiades])
    end

    it 'orders instances newest-commit first' do
      c1 = commit_with_sha('a' * 40, commit_time: 3.days.ago)
      c2 = commit_with_sha('b' * 40, commit_time: 2.days.ago)
      c3 = commit_with_sha('c' * 40, commit_time: 1.day.ago)
      tcc1 = create(:test_case_commit, :passing, commit: c1, test_case: test_case)
      tcc2 = create(:test_case_commit, :passing, commit: c2, test_case: test_case)
      tcc3 = create(:test_case_commit, :passing, commit: c3, test_case: test_case)
      instance_on(tcc: tcc1, computer: computer_a)
      instance_on(tcc: tcc2, computer: computer_a)
      instance_on(tcc: tcc3, computer: computer_a)

      # Entries arrive newest-first from commit_window
      entries = [make_entry(c3, tcc3), make_entry(c2, tcc2), make_entry(c1, tcc1)]
      payload = helper.submissions_payload(entries, chosen_name: "pleiades")
      commit_shas = payload[:instances].map { |ti| payload[:commit_for][ti.id].short_sha }
      expect(commit_shas).to eq([c3.short_sha, c2.short_sha, c1.short_sha])
    end

    it 'gracefully handles an empty entries array' do
      payload = helper.submissions_payload([])
      expect(payload).to eq(chosen: nil, options: [], instances: [], commit_for: {})
    end
  end
end
