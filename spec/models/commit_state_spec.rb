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

    it 'treats a singleton submission with no compile flag as built when it carries a test instance' do
      # Test-by-test clients submit each result on its own with no
      # `entire`/`empty` flag, so the submissions controller leaves
      # `compiled` nil. The presence of a test instance implies the
      # build succeeded.
      submit(computer: rusty, compiled: nil)
      instance(test_case: test_case_a, computer: rusty, passed: true)
      expect(commit.reload.build_status).to eq(:all_ok)
    end

    it 'still returns :unknown for a compile-less submission with no test instances' do
      # An empty singleton submission carries no signal at all — don't
      # invent a build status for it.
      submit(computer: rusty, compiled: nil)
      expect(commit.reload.build_status).to eq(:unknown)
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

    # Claim awareness: see docs/dispatcher-and-claims.md. Pre-claims,
    # the only signal we had for "in flight" was "the TCC has no
    # submissions yet," which fires the instant a commit is ingested.
    # Claims give us the real signal; tests_status keys :pending /
    # :not_run off claim presence now.
    describe 'claim-aware pending vs not_run' do
      it 'is :not_run for a fresh commit with TCCs but no claims' do
        [test_case_a, test_case_b, test_case_c].each { |tc| tcc_for(tc) }
        expect(commit.reload.tests_status).to eq(:not_run)
      end

      it 'is :pending when at least one claim is open on the commit' do
        [test_case_a, test_case_b, test_case_c].each { |tc| tcc_for(tc) }
        create(:claim, computer: rusty, commit: commit)

        expect(commit.reload.tests_status).to eq(:pending)
      end

      it 'is :pending_partial when claims are open AND some tests have passed' do
        [test_case_a, test_case_b, test_case_c].each { |tc| tcc_for(tc) }
        submit(computer: rusty)
        instance(test_case: test_case_a, computer: rusty, passed: true)
        tcc_for(test_case_a).update_status
        tcc_for(test_case_a).save!

        create(:claim, computer: popeye, commit: commit)

        expect(commit.reload.tests_status).to eq(:pending_partial)
      end

      it 'reverts to :not_run after the only open claim is fulfilled' do
        [test_case_a, test_case_b, test_case_c].each { |tc| tcc_for(tc) }
        claim = create(:claim, computer: rusty, commit: commit)
        expect(commit.reload.tests_status).to eq(:pending)

        claim.fulfill!
        expect(commit.reload.tests_status).to eq(:not_run)
      end

      it 'reverts to :not_run after the only open claim expires' do
        [test_case_a, test_case_b, test_case_c].each { |tc| tcc_for(tc) }
        create(:claim, :expired, computer: rusty, commit: commit)
        expect(commit.reload.tests_status).to eq(:not_run)
      end
    end
  end

  describe '#has_pending_claims?' do
    it 'is false on a commit with no claims' do
      expect(commit.has_pending_claims?).to be false
    end

    it 'is true when at least one pending claim exists' do
      create(:claim, computer: rusty, commit: commit)
      expect(commit.has_pending_claims?).to be true
    end

    it 'is false when the only claim has been fulfilled' do
      create(:claim, :fulfilled, computer: rusty, commit: commit)
      expect(commit.has_pending_claims?).to be false
    end

    it 'is false when the only claim has expired' do
      create(:claim, :expired, computer: rusty, commit: commit)
      expect(commit.has_pending_claims?).to be false
    end

    it 'works without preloading the association' do
      create(:claim, computer: rusty, commit: commit)
      expect(commit.reload.has_pending_claims?).to be true
    end

    it 'short-circuits to the loaded association when preloaded' do
      # If `has_pending_claims?` triggered a DB query despite the
      # preload, the commits index render path would N+1 across 25
      # rows. Verify by clearing the connection's query cache and
      # asserting the predicate doesn't issue a SELECT.
      create(:claim, computer: rusty, commit: commit)
      reloaded = Commit.includes(:pending_claims).find(commit.id)
      query_count = 0
      counter = ->(*, payload) {
        query_count += 1 unless payload[:name] == "SCHEMA"
      }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        reloaded.has_pending_claims?
      end
      expect(query_count).to eq(0)
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

    it 'reports tests with no built-computer results AND no claims as not pending' do
      # Every computer attempted to build and failed; the commit has
      # TCCs but no claims. Pre-claims this used to lump all three
      # tests into `pending_tests` because of the "no_data ⇒ pending"
      # fallback in `commit_state`. With claims as the real "work in
      # flight" signal, "all builds failed and nobody's retrying"
      # correctly aggregates to zero pending tests (and the hero
      # tile reads as :not_run).
      all_computers.each { |c| submit(computer: c, compiled: false) }
      [test_case_a, test_case_b, test_case_c].each { |tc| tcc_for(tc) }

      state = commit.reload.commit_state
      expect(state[:tests][:pending_tests]).to eq(0)
      expect(state[:tests][:status]).to eq(:not_run)
    end

    it 'counts tests with open test-scope claims as pending in the hero stat row' do
      # Same shape as the prior test, but with two test-scope claims
      # out on test_case_a and test_case_b. Those are the tests
      # someone is actually working on, so they get counted; the
      # un-claimed test_case_c does not.
      all_computers.each { |c| submit(computer: c, compiled: false) }
      [test_case_a, test_case_b, test_case_c].each { |tc| tcc_for(tc) }

      create(:claim, :test_scope, computer: rusty, commit: commit,
                                  test_case_commit: tcc_for(test_case_a))
      create(:claim, :test_scope, computer: popeye, commit: commit,
                                  test_case_commit: tcc_for(test_case_b))

      state = commit.reload.commit_state
      expect(state[:tests][:pending_tests]).to eq(2)
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

  describe '#default_detail_tab' do
    it 'opens Computers when a build failed' do
      submit(computer: rusty, compiled: false)
      submit(computer: popeye, compiled: true)
      instance(test_case: test_case_a, computer: popeye, passed: true)
      expect(commit.reload.default_detail_tab).to eq(:computers)
    end

    it 'opens Summary when builds are fine — the merged matrix tab carries the test view' do
      submit(computer: rusty)
      submit(computer: popeye)
      instance(test_case: test_case_a, computer: rusty, passed: false)
      instance(test_case: test_case_a, computer: popeye, passed: false)
      expect(commit.reload.default_detail_tab).to eq(:summary)
    end

    it 'opens Summary when nothing is broken' do
      build_clean_scenario
      expect(commit.reload.default_detail_tab).to eq(:summary)
    end
  end

  describe '#per_computer_summary' do
    it 'returns one row per computer, sorted worst-first' do
      submit(computer: rusty, compiled: false)
      submit(computer: popeye)
      submit(computer: derecho)
      instance(test_case: test_case_a, computer: popeye, passed: false)
      instance(test_case: test_case_a, computer: derecho, passed: true)

      rows = commit.reload.per_computer_summary
      expect(rows.map { |r| r[:computer].name }).to eq(%w[rusty popeye derecho])
      expect(rows.first[:state]).to eq(:build_fail)
      expect(rows[1][:state]).to eq(:fail)
      expect(rows.last[:state]).to eq(:all_pass)
    end

    it 'counts pass/fail/fpe per computer' do
      submit(computer: popeye)
      instance(test_case: test_case_a, computer: popeye, passed: true, fpe_checks: true)
      instance(test_case: test_case_b, computer: popeye, passed: false)

      row = commit.reload.per_computer_summary.find { |r| r[:computer].name == 'popeye' }
      expect(row[:counts][:pass]).to eq(1)
      expect(row[:counts][:fail]).to eq(1)
      expect(row[:counts][:fpe]).to eq(1)
    end

    it 'includes computers whose only submissions carry no compile flag but have results' do
      # Regression: singleton submissions (compiled=nil) used to drop
      # the computer out of the per-computer summary entirely, which
      # hid the matrix column even though the test_instances were
      # safely in the database.
      submit(computer: popeye, compiled: nil)
      instance(test_case: test_case_a, computer: popeye, passed: true)

      row = commit.reload.per_computer_summary.find { |r| r[:computer].name == 'popeye' }
      expect(row).not_to be_nil
      expect(row[:state]).to eq(:all_pass)
      expect(row[:counts][:pass]).to eq(1)
    end
  end

  describe '#per_test_summary' do
    before do
      submit(computer: rusty)
      submit(computer: popeye)
    end

    it 'classifies a uniformly-failing test as :fail' do
      instance(test_case: test_case_a, computer: rusty, passed: false)
      instance(test_case: test_case_a, computer: popeye, passed: false)
      row = commit.reload.per_test_summary.find { |r| r[:test_case] == test_case_a }
      expect(row[:overall]).to eq(:fail)
    end

    it 'classifies a mixed-pass/fail test as :mixed' do
      instance(test_case: test_case_a, computer: rusty, passed: true)
      instance(test_case: test_case_a, computer: popeye, passed: false)
      row = commit.reload.per_test_summary.find { |r| r[:test_case] == test_case_a }
      expect(row[:overall]).to eq(:mixed)
    end

    it 'classifies a passing-but-flagged test as :flagged' do
      instance(test_case: test_case_a, computer: rusty, passed: true, fpe_checks: true)
      instance(test_case: test_case_a, computer: popeye, passed: true)
      row = commit.reload.per_test_summary.find { |r| r[:test_case] == test_case_a }
      expect(row[:overall]).to eq(:flagged)
    end

    it 'classifies a test that passed on some computers and has pending neighbors as :pass' do
      # The user's rule: any passing submission + no failures or
      # checksum mismatches → test is passing, regardless of
      # whether other computers have reported yet. The matrix view
      # is where the user investigates which computers haven't
      # submitted yet.
      Submission.where(commit: commit).delete_all
      submit(computer: rusty)   # compiled
      submit(computer: popeye)  # compiled but won't run test_case_a
      instance(test_case: test_case_a, computer: rusty, passed: true)
      # popeye doesn't submit a test_instance — its cell will be
      # :pending in the matrix.

      row = commit.reload.per_test_summary.find { |r| r[:test_case] == test_case_a }
      expect(row[:overall]).to eq(:pass)
    end

    it 'classifies a test with no built-computer results as :not_run' do
      # Override the `before` block: every submission failed to
      # compile, so the matrix's filter-to-built leaves the row
      # empty. Without this clause `per_test_summary` used to fall
      # through to `:pass` and the Tests tab rendered the row green.
      Submission.where(commit: commit).delete_all
      submit(computer: rusty, compiled: false)
      submit(computer: popeye, compiled: false)
      tcc_for(test_case_a)

      row = commit.reload.per_test_summary.find { |r| r[:test_case] == test_case_a }
      expect(row[:overall]).to eq(:not_run)
    end

    it 'sorts failing tests above passing ones' do
      instance(test_case: test_case_a, computer: rusty, passed: true)
      instance(test_case: test_case_a, computer: popeye, passed: true)
      instance(test_case: test_case_b, computer: rusty, passed: false)
      instance(test_case: test_case_b, computer: popeye, passed: false)
      overalls = commit.reload.per_test_summary.map { |r| r[:overall] }
      expect(overalls.first).to eq(:fail)
    end

    it 'orders tests within the same status by TestCase.modules (star, binary, astero)' do
      # All passing; sort within :pass should follow the module
      # ranking rather than alphabetical order on the module name.
      [test_case_a, test_case_b, test_case_c].each do |tc|
        [rusty, popeye].each { |c| instance(test_case: tc, computer: c, passed: true) }
      end

      passing_rows = commit.reload.per_test_summary.select { |r| r[:overall] == :pass }
      modules = passing_rows.map { |r| r[:test_case].module }
      # The three fixtures are: irradiated_planet (binary),
      # 1_5M_with_diffusion (star), pisn (star). With star-first
      # ordering the star tests should come before binary.
      expect(modules.take(2)).to eq(%w[star star])
      expect(modules.last).to eq("binary")
    end
  end

  describe '#cells_changed_since' do
    let(:other_commit) { create(:commit) }

    def setup_clean_other
      submit(computer: rusty)
      submit(computer: popeye)
      create(:submission, commit: other_commit, computer: rusty, compiled: true)
      create(:submission, commit: other_commit, computer: popeye, compiled: true)
      [test_case_a, test_case_b].each do |tc|
        other_tcc = create(:test_case_commit, commit: other_commit, test_case: tc)
        [rusty, popeye].each do |comp|
          other_sub = Submission.find_by(commit: other_commit, computer: comp)
          create(:test_instance, commit: other_commit, computer: comp,
                 test_case: tc, test_case_commit: other_tcc, submission: other_sub,
                 passed: true)
        end
      end
    end

    it 'returns no rows when nothing regressed' do
      setup_clean_other
      [test_case_a, test_case_b].each do |tc|
        [rusty, popeye].each { |c| instance(test_case: tc, computer: c, passed: true) }
      end
      diff = commit.reload.cells_changed_since(other_commit.reload)
      expect(diff).to eq([])
    end

    it 'flags newly-failing cells as :new_failure' do
      setup_clean_other
      instance(test_case: test_case_a, computer: rusty, passed: false)
      instance(test_case: test_case_a, computer: popeye, passed: true)
      diff = commit.reload.cells_changed_since(other_commit.reload)
      expect(diff).to include(
        hash_including(test_case_id: test_case_a.id, computer_id: rusty.id,
                       change: :new_failure)
      )
    end

    it 'flags newly-FPE cells as :new_flag' do
      setup_clean_other
      instance(test_case: test_case_a, computer: rusty, passed: true, fpe_checks: true)
      instance(test_case: test_case_a, computer: popeye, passed: true)
      diff = commit.reload.cells_changed_since(other_commit.reload)
      expect(diff).to include(
        hash_including(change: :new_flag, flag_kind: :fpe,
                       test_case_id: test_case_a.id, computer_id: rusty.id)
      )
    end

    it 'returns [] when the other commit is nil' do
      expect(commit.cells_changed_since(nil)).to eq([])
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

  describe '#commit_neighbors' do
    let(:branch) { create(:branch, name: 'main') }
    let(:commits) do
      3.times.map do |i|
        c = create(:commit, commit_time: i.days.ago)
        BranchMembership.create!(branch: branch, commit: c)
        c
      end.tap do |list|
        branch.update!(head: list.first)
        CommitRelation.create!(parent: list[1], child: list[0], parent_index: 0)
        CommitRelation.create!(parent: list[2], child: list[1], parent_index: 0)
      end
    end

    it 'returns the immediate older and newer commits' do
      newest, middle, oldest = commits
      neighbors = branch.commit_neighbors(middle)
      expect(neighbors[:older]).to eq(oldest)
      expect(neighbors[:newer]).to eq(newest)
    end

    it 'returns nil for the older slot at the oldest commit' do
      _, _, oldest = commits
      neighbors = branch.commit_neighbors(oldest)
      expect(neighbors[:older]).to be_nil
      expect(neighbors[:newer]).not_to be_nil
    end

    it 'returns nil for the newer slot at the head commit' do
      newest, = commits
      neighbors = branch.commit_neighbors(newest)
      expect(neighbors[:newer]).to be_nil
      expect(neighbors[:older]).not_to be_nil
    end
  end

  describe '#focused_commit_window' do
    let(:branch) { create(:branch, name: 'main') }
    # Five commits, newest-first: c0 (newest) → c4 (oldest).
    let(:commits) do
      list = 5.times.map do |i|
        c = create(:commit, commit_time: i.days.ago)
        BranchMembership.create!(branch: branch, commit: c)
        c
      end
      branch.update!(head: list.first)
      list.each_cons(2) do |newer, older|
        CommitRelation.create!(parent: older, child: newer, parent_index: 0)
      end
      list
    end

    it 'centers the window with two newer and two older when the focused commit is in the middle' do
      window = branch.focused_commit_window(commits[2], size: 5)
      expect(window.map(&:short_sha)).to eq(commits.map(&:short_sha))
    end

    it 'pulls extra older commits when the focused commit is the head' do
      window = branch.focused_commit_window(commits[0], size: 5)
      expect(window.first).to eq(commits[0])
      expect(window.size).to eq(5)
      expect(window).to eq(commits) # head + 4 older
    end

    it 'pulls extra newer commits when the focused commit is the oldest' do
      window = branch.focused_commit_window(commits.last, size: 5)
      expect(window.last).to eq(commits.last)
      expect(window.size).to eq(5)
      expect(window).to eq(commits) # 4 newer + oldest
    end

    it 'returns just the focused commit when the branch has only one' do
      lone_branch = create(:branch, name: 'lone')
      c = create(:commit, commit_time: Time.current)
      BranchMembership.create!(branch: lone_branch, commit: c)
      lone_branch.update!(head: c)
      expect(lone_branch.focused_commit_window(c)).to eq([c])
    end
  end

  describe '#last_clean_commit_before' do
    let(:branch) { create(:branch, name: 'main') }
    let(:user) { create(:user) }
    let(:rusty) { create(:computer, name: 'rusty', user: user) }
    let!(:test_case) { create(:test_case, name: 'irradiated_planet', module: 'binary') }

    def commit_with_state(time:, all_pass:)
      c = create(:commit, commit_time: time)
      BranchMembership.create!(branch: branch, commit: c)
      sub = create(:submission, commit: c, computer: rusty, compiled: true)
      tcc = create(:test_case_commit, commit: c, test_case: test_case)
      create(:test_instance, commit: c, computer: rusty, test_case: test_case,
             test_case_commit: tcc, submission: sub, passed: all_pass)
      c
    end

    it 'returns the most recent older commit that is all-built and all-pass' do
      newest = commit_with_state(time: 0.days.ago, all_pass: false)
      middle = commit_with_state(time: 1.day.ago,  all_pass: false)
      oldest = commit_with_state(time: 2.days.ago, all_pass: true)
      branch.update!(head: newest)
      CommitRelation.create!(parent: middle, child: newest, parent_index: 0)
      CommitRelation.create!(parent: oldest, child: middle, parent_index: 0)

      expect(branch.last_clean_commit_before(newest)).to eq(oldest)
    end

    it 'returns nil when no older commit is clean' do
      newest = commit_with_state(time: 0.days.ago, all_pass: false)
      older  = commit_with_state(time: 1.day.ago,  all_pass: false)
      branch.update!(head: newest)
      CommitRelation.create!(parent: older, child: newest, parent_index: 0)
      expect(branch.last_clean_commit_before(newest)).to be_nil
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

  describe '#has_pending_claims? and #pending?' do
    let(:user) { create(:user) }
    let(:computer) { create(:computer, user: user) }
    let(:commit) { create(:commit) }
    let(:test_case) { create(:test_case) }
    let(:tcc) { create(:test_case_commit, commit: commit, test_case: test_case) }

    it '#has_pending_claims? is false on a TCC with no claims' do
      expect(tcc.has_pending_claims?).to be false
    end

    it '#has_pending_claims? is true with a pending test-scope claim' do
      create(:claim, :test_scope, computer: computer, commit: commit,
                                  test_case_commit: tcc)
      expect(tcc.has_pending_claims?).to be true
    end

    it '#has_pending_claims? is false when the only claim has been fulfilled' do
      create(:claim, :test_scope, :fulfilled,
             computer: computer, commit: commit, test_case_commit: tcc)
      expect(tcc.has_pending_claims?).to be false
    end

    it '#pending? is true when status is -1 and there is a pending claim' do
      create(:claim, :test_scope, computer: computer, commit: commit,
                                  test_case_commit: tcc)
      expect(tcc.pending?).to be true
    end

    it "#pending? is false when status is -1 and there's no claim" do
      expect(tcc.pending?).to be false
    end

    it '#pending? is false once the TCC has any non-untested status' do
      # Mid-run: a test-scope claim is out AND a passing instance has
      # already landed. The TCC's status flips to passing(=0) and
      # #pending? reads as false even though the claim row is still
      # pending — the test no longer needs work.
      create(:claim, :test_scope, computer: computer, commit: commit,
                                  test_case_commit: tcc)
      sub = create(:submission, commit: commit, computer: computer)
      create(:test_instance, commit: commit, computer: computer,
                             test_case: test_case, test_case_commit: tcc,
                             submission: sub, passed: true)
      tcc.update_status
      tcc.save!
      expect(tcc.pending?).to be false
    end
  end
end
