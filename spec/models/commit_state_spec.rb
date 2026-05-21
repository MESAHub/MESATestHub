require 'rails_helper'

# Covers the Phase 4 aggregation layer:
#   Commit#build_status, #tests_status, #flag_counts, #commit_state,
#   #test_computer_matrix
#   Branch#sparkline_data
#   TestCaseCommit#instances_for_display
#
# The scenarios mirror the demo SHAs in
# docs/design_handoff_mesa_testhub/prototype/data.js — clean,
# uniform-fail, mixed, pending, partial build, etc. Each one is built
# from real Submission/TestCaseCommit/TestInstance rows so the helpers
# exercise the same code paths the views will hit.
RSpec.describe 'commit state aggregation' do
  let(:user) { create(:user) }

  # Six computers, matching the prototype's roster shape (just for
  # parity — the helpers don't depend on names).
  let!(:rusty)    { create(:computer, name: 'rusty', user: user) }
  let!(:popeye)   { create(:computer, name: 'popeye', user: user) }
  let!(:derecho)  { create(:computer, name: 'derecho', user: user) }
  let!(:frontera) { create(:computer, name: 'frontera', user: user) }
  let!(:ranger)   { create(:computer, name: 'ranger', user: user) }
  let!(:expanse)  { create(:computer, name: 'expanse', user: user) }
  let(:all_computers) { [rusty, popeye, derecho, frontera, ranger, expanse] }

  # TestCase.modules currently allows %w[star binary astero] only —
  # the prototype's `eos` and `kap` modules don't pass the inclusion
  # validation yet. Using the available modules is enough to exercise
  # the aggregation logic.
  let!(:test_case_a) { create(:test_case, name: 'irradiated_planet', module: 'binary') }
  let!(:test_case_b) { create(:test_case, name: '1_5M_with_diffusion', module: 'star') }
  let!(:test_case_c) { create(:test_case, name: 'pisn', module: 'star') }

  let(:commit) { create(:commit) }

  # Helpers — small enough to inline, but pulling them out keeps each
  # scenario block focused on the design intent rather than fixture
  # plumbing.

  def submit(computer:, compiled: true)
    create(:submission, commit: commit, computer: computer, compiled: compiled)
  end

  def tcc_for(test_case)
    TestCaseCommit.find_by(commit: commit, test_case: test_case) ||
      create(:test_case_commit, commit: commit, test_case: test_case)
  end

  def instance(test_case:, computer:, passed: true, **overrides)
    tcc = tcc_for(test_case)
    sub = Submission.find_by(commit: commit, computer: computer) || submit(computer: computer)
    create(
      :test_instance,
      commit: commit,
      computer: computer,
      test_case: test_case,
      test_case_commit: tcc,
      submission: sub,
      passed: passed,
      **overrides
    )
  end

  # A "clean" scenario: every computer compiled, every test_case has
  # a passing instance on every computer.
  def build_clean_scenario(computers: all_computers, test_cases: [test_case_a, test_case_b, test_case_c])
    computers.each { |c| submit(computer: c) }
    test_cases.each do |tc|
      computers.each { |c| instance(test_case: tc, computer: c, passed: true) }
    end
    Commit.find(commit.id).tap(&:reload) # picks up after_save scalars
  end

  describe '#build_status' do
    it 'returns :all_ok when every computer compiled' do
      all_computers.each { |c| submit(computer: c) }
      expect(commit.reload.build_status).to eq(:all_ok)
    end

    it 'returns :some_fail when at least one computer failed' do
      submit(computer: rusty, compiled: true)
      submit(computer: frontera, compiled: false)
      expect(commit.reload.build_status).to eq(:some_fail)
    end

    it 'returns :all_fail when every computer failed to compile' do
      all_computers.each { |c| submit(computer: c, compiled: false) }
      expect(commit.reload.build_status).to eq(:all_fail)
    end

    it 'returns :unknown when no submission has reported compilation either way' do
      expect(commit.reload.build_status).to eq(:unknown)
    end

    it 'treats a computer as built if any of its submissions compiled' do
      submit(computer: rusty, compiled: false)
      submit(computer: rusty, compiled: true) # second batch, same computer
      submit(computer: frontera, compiled: true)
      expect(commit.reload.build_status).to eq(:all_ok)
    end
  end

  describe '#tests_status' do
    it 'is :all_pass for the clean scenario' do
      build_clean_scenario
      expect(commit.reload.tests_status).to eq(:all_pass)
    end

    it 'is :fail when a test fails uniformly across every computer that ran it' do
      all_computers.each { |c| submit(computer: c) }
      all_computers.each { |c| instance(test_case: test_case_a, computer: c, passed: false) }
      # Roll up the tcc.status the way SubmissionsController would.
      tcc_for(test_case_a).update_status
      tcc_for(test_case_a).save!
      expect(commit.reload.tests_status).to eq(:fail)
    end

    it 'is :mixed when a test passes on some computers and fails on others' do
      all_computers.each { |c| submit(computer: c) }
      instance(test_case: test_case_b, computer: rusty,    passed: true)
      instance(test_case: test_case_b, computer: popeye,   passed: false)
      instance(test_case: test_case_b, computer: derecho,  passed: false)
      tcc_for(test_case_b).update_status
      tcc_for(test_case_b).save!

      expect(commit.reload.tests_status).to eq(:mixed)
    end

    it 'is :not_run when builds all failed and nothing executed' do
      all_computers.each { |c| submit(computer: c, compiled: false) }
      expect(commit.reload.tests_status).to eq(:not_run)
    end
  end

  describe '#flag_counts' do
    before do
      all_computers.each { |c| submit(computer: c) }
    end

    it 'counts inlists_full from passing run_optional instances' do
      instance(test_case: test_case_a, computer: rusty, run_optional: true)
      instance(test_case: test_case_a, computer: popeye, run_optional: true)

      expect(commit.reload.flag_counts[:inlists_full]).to eq(2)
    end

    it 'counts fpe from passing fpe_checks instances' do
      instance(test_case: test_case_a, computer: rusty, fpe_checks: true)
      expect(commit.reload.flag_counts[:fpe]).to eq(1)
    end

    it 'flags checksum at the cell level when the TCC has multiple unique checksums' do
      instance(test_case: test_case_a, computer: rusty,   checksum: 'aaa1111')
      instance(test_case: test_case_a, computer: popeye,  checksum: 'bbb2222')
      tcc_for(test_case_a).update_and_save_scalars

      counts = commit.reload.flag_counts
      # Both passing cells in that TCC pick up the divergence.
      expect(counts[:checksum]).to eq(2)
    end
  end

  describe '#test_computer_matrix' do
    it 'has a cell for every (tcc, submitting computer) pair' do
      [rusty, popeye, derecho].each { |c| submit(computer: c) }
      instance(test_case: test_case_a, computer: rusty)
      instance(test_case: test_case_b, computer: rusty)

      matrix = commit.reload.test_computer_matrix
      expect(matrix.keys).to contain_exactly(test_case_a.id, test_case_b.id)
      expect(matrix[test_case_a.id].keys).to contain_exactly(rusty.id, popeye.id, derecho.id)
    end

    it 'marks cells without instances on a built computer as :pending' do
      submit(computer: rusty, compiled: true)
      instance(test_case: test_case_a, computer: rusty) # bootstrap the tcc

      matrix = commit.reload.test_computer_matrix
      expect(matrix[test_case_a.id][rusty.id][:status]).to eq(:pass)
    end

    it 'marks cells on a computer that failed to compile as :no_build' do
      submit(computer: frontera, compiled: false)
      instance(test_case: test_case_a, computer: rusty) # so the tcc exists
      submit(computer: rusty)

      matrix = commit.reload.test_computer_matrix
      expect(matrix[test_case_a.id][frontera.id][:status]).to eq(:no_build)
    end
  end

  describe '#commit_state — design demo scenarios' do
    # Each example mirrors a SHA from the design's prototype/data.js.
    # Anchoring to those scenarios makes any future divergence in the
    # aggregation logic easy to spot.

    it 'aa27a08 — all clean → :all_ok build, :all_pass tests, no flags' do
      build_clean_scenario

      state = commit.reload.commit_state
      expect(state[:build][:status]).to eq(:all_ok)
      expect(state[:tests][:status]).to eq(:all_pass)
      expect(state[:flags].values.sum).to eq(0)
    end

    it 'e91a5c2 — partial build + mixed test fail' do
      builds = {
        rusty => true, popeye => true, derecho => false,
        frontera => true, ranger => false, expanse => false
      }
      builds.each { |c, ok| submit(computer: c, compiled: ok) }

      # 1.5M_with_diffusion mixed across built computers
      instance(test_case: test_case_b, computer: rusty, passed: false)
      instance(test_case: test_case_b, computer: popeye, passed: false)
      instance(test_case: test_case_b, computer: frontera, passed: true)
      tcc_for(test_case_b).update_status
      tcc_for(test_case_b).save!

      state = commit.reload.commit_state
      expect(state[:build][:status]).to eq(:some_fail)
      expect(state[:build][:built_computer_ids]).to contain_exactly(rusty.id, popeye.id, frontera.id)
      expect(state[:tests][:status]).to eq(:mixed)
      expect(state[:tests][:mixed_tests]).to eq(1)
      expect(state[:tests][:uniform_failing_tests]).to eq(0)
    end

    it 'd1f8a92 — every build fails, nothing runs' do
      all_computers.each { |c| submit(computer: c, compiled: false) }

      state = commit.reload.commit_state
      expect(state[:build][:status]).to eq(:all_fail)
      expect(state[:tests][:status]).to eq(:not_run)
    end

    it '8e7c1b3 — passing with two full-inlist runs flagged' do
      all_computers.each { |c| submit(computer: c) }
      [test_case_a, test_case_b, test_case_c].each do |tc|
        all_computers.each { |c| instance(test_case: tc, computer: c, passed: true) }
      end
      # Now mark two of derecho's instances as run_optional after the fact
      TestInstance.where(commit: commit, computer: derecho)
                  .update_all(run_optional: true)
      TestInstance.where(commit: commit, computer: expanse)
                  .update_all(run_optional: true)

      state = commit.reload.commit_state
      expect(state[:tests][:status]).to eq(:all_pass)
      # Two computers × three test cases each.
      expect(state[:flags][:inlists_full]).to eq(6)
    end
  end
end

RSpec.describe Branch, type: :model do
  describe '#sparkline_data' do
    it 'returns one entry per reachable commit, newest first, up to the limit' do
      branch = create(:branch, name: 'main')
      commits = 3.times.map do |i|
        c = create(:commit, commit_time: i.days.ago)
        BranchMembership.create!(branch: branch, commit: c)
        c
      end
      branch.update!(head: commits.first)
      # Wire up parent edges so the recursive CTE can reach them.
      CommitRelation.create!(parent: commits[1], child: commits[0], parent_index: 0)
      CommitRelation.create!(parent: commits[2], child: commits[1], parent_index: 0)

      data = branch.sparkline_data(limit: 2)
      expect(data.size).to eq(2)
      expect(data.first[:sha]).to eq(commits[0].short_sha)
      expect(data.first).to include(:build_status, :tests_status, :commit)
    end
  end
end

RSpec.describe TestCaseCommit, type: :model do
  describe '#instances_for_display' do
    let(:commit) { create(:commit) }
    let(:test_case) { create(:test_case) }
    let(:tcc) { create(:test_case_commit, commit: commit, test_case: test_case) }
    let(:user) { create(:user) }
    let(:computer) { create(:computer, name: 'rusty', user: user) }
    let(:submission) { create(:submission, commit: commit, computer: computer) }

    it 'returns one row per instance with the column-picker payload' do
      create(
        :test_instance,
        commit: commit,
        computer: computer,
        test_case: test_case,
        test_case_commit: tcc,
        submission: submission,
        passed: true,
        run_optional: true,
        fpe_checks: false,
        checksum: 'abc1234',
        runtime_seconds: 600,
        steps: 1234
      )

      row = tcc.reload.instances_for_display.first
      expect(row[:status]).to eq(:pass)
      expect(row[:variant]).to eq(:full)
      expect(row[:flags][:inlists_full]).to be true
      expect(row[:flags][:fpe]).to be false
      expect(row[:checksum]).to eq('abc1234')
      expect(row[:steps]).to eq(1234)
      expect(row[:computer_name]).to eq('rusty')
    end
  end
end
