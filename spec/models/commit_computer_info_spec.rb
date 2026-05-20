require 'rails_helper'

# Locks in the contract Commit#computer_info exposes to the view. The
# show page renders entry[:computer].user.name, entry[:spec],
# entry[:frac], entry[:compilation], etc. — any refactor that batches the
# queries has to keep all of that working.
RSpec.describe Commit, '#computer_info' do
  let(:user) { create(:user, name: 'Sam Submitter') }
  let(:linux_computer) do
    create(:computer, user: user, name: 'linux-box', platform: 'linux')
  end
  let(:mac_computer) do
    create(:computer, user: user, name: 'mac-box', platform: 'macOS')
  end
  let(:commit) { create(:commit) }
  let(:test_case_a) { create(:test_case, name: 'tc_a', module: 'star') }
  let(:test_case_b) { create(:test_case, name: 'tc_b', module: 'star') }

  def make_submission(computer:, compiler:, compiler_version:, compiled:,
                      platform_version: '24.0', sdk_version: nil,
                      math_backend: nil)
    Submission.create!(
      commit: commit, computer: computer,
      entire: true, empty: false,
      compiler: compiler, compiler_version: compiler_version,
      compiled: compiled,
      platform_version: platform_version,
      sdk_version: sdk_version,
      math_backend: math_backend
    )
  end

  def make_test_instance(computer:, test_case:, computer_specification:,
                         submission:)
    TestInstance.create!(
      commit: commit, computer: computer, test_case: test_case,
      submission: submission,
      compiler: 'gfortran',
      passed: true,
      computer_specification: computer_specification,
      computer_name: computer.name
    )
  end

  context 'with no submissions' do
    it 'returns an empty array' do
      expect(commit.computer_info).to eq([])
    end
  end

  context 'with one submission and one test instance' do
    before do
      submission = make_submission(computer: linux_computer, compiler: 'gfortran',
                                   compiler_version: '13.2.0', compiled: true)
      # Both test cases get a TestCaseCommit (the denominator is the count
      # of test cases the commit *should* run, not the number a single
      # computer has actually run).
      TestCaseCommit.create!(commit: commit, test_case: test_case_a)
      TestCaseCommit.create!(commit: commit, test_case: test_case_b)
      # The spec string must match what Submission#computer_specification
      # would produce for that submission, since the numerator query is
      # joined on (computer_id, computer_specification).
      spec = "linux 24.0 gfortran 13.2.0"
      make_test_instance(computer: linux_computer, test_case: test_case_a,
                         computer_specification: spec, submission: submission)
    end

    it 'returns one entry with the expected shape' do
      info = commit.computer_info
      expect(info.size).to eq(1)
      entry = info.first
      expect(entry[:computer]).to eq(linux_computer)
      expect(entry[:spec]).to eq('linux 24.0 gfortran 13.2.0')
      expect(entry[:numerator]).to eq(1)
      expect(entry[:denominator]).to eq(2)
      expect(entry[:frac]).to be_within(0.001).of(0.5)
      expect(entry[:compilation]).to eq(:success)
    end

    it 'returns the user via entry[:computer].user without further DB hits' do
      info = commit.computer_info
      # The view does `entry[:computer].user.name` — make sure that path
      # actually has a loaded user association.
      expect(info.first[:computer].association(:user)).to be_loaded
    end
  end

  context 'with multiple specs from the same computer' do
    before do
      make_submission(computer: linux_computer, compiler: 'gfortran',
                      compiler_version: '13.2.0', compiled: true)
      make_submission(computer: linux_computer, compiler: 'ifort',
                      compiler_version: '2021.10', compiled: false)
      test_case_a; test_case_b
    end

    it 'returns one entry per unique spec' do
      expect(commit.computer_info.size).to eq(2)
    end

    it 'reports :mixed for every entry of a computer with both true and false compiled across specs' do
      # Existing semantics: compilation status is rolled up per computer,
      # not per spec. If a computer's submissions contain both true and
      # false compiled values across any of its specs, every spec entry
      # for that computer reports :mixed.
      compilations = commit.computer_info.map { |e| e[:compilation] }
      expect(compilations).to all(eq(:mixed))
    end
  end

  context 'with mixed compilation results across submissions of the same spec' do
    before do
      make_submission(computer: linux_computer, compiler: 'gfortran',
                      compiler_version: '13.2.0', compiled: true)
      make_submission(computer: linux_computer, compiler: 'gfortran',
                      compiler_version: '13.2.0', compiled: false)
      test_case_a
    end

    it 'reports :mixed when the same spec has both true and false compiled values' do
      expect(commit.computer_info.first[:compilation]).to eq(:mixed)
    end
  end

  context 'with nil compiled across all submissions for a spec' do
    before do
      make_submission(computer: linux_computer, compiler: 'gfortran',
                      compiler_version: '13.2.0', compiled: nil)
      test_case_a
    end

    it 'reports :unknown' do
      expect(commit.computer_info.first[:compilation]).to eq(:unknown)
    end
  end

  describe 'query count' do
    # Pre-refactor, computer_info ran roughly four queries per unique spec
    # (Computer.find, sub.computer.platform, ti.where, submissions.where).
    # The new implementation batches everything, so query count should be
    # constant regardless of how many specs there are. This test fails
    # loudly if anyone reintroduces a per-spec query.
    it 'does not scale with the number of unique specs' do
      6.times do |i|
        make_submission(
          computer: i.even? ? linux_computer : mac_computer,
          compiler: 'gfortran', compiler_version: "13.2.#{i}",
          compiled: i.odd?
        )
      end
      test_case_a

      query_count = 0
      subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
        next if payload[:name] == 'SCHEMA'
        next if payload[:sql] =~ /\A(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/
        query_count += 1
      end

      commit.computer_info

      ActiveSupport::Notifications.unsubscribe(subscriber)

      # Reasonable headroom for the fixed set of queries
      # (submissions+computer+user, ti grouping, test_cases.count, etc.).
      # The old implementation would be ~25+ here with six specs across
      # two computers.
      expect(query_count).to be <= 8
    end
  end
end
