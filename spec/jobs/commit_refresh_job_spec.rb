require 'rails_helper'

# The deferred path: results flag stored scalars stale, and one
# CommitRefreshJob per burst recomputes them. The rest of the suite runs
# with config.x.defer_scalar_refresh off (inline refresh), so this spec
# turns it on.
RSpec.describe CommitRefreshJob do
  include ActiveJob::TestHelper

  around do |example|
    Rails.configuration.x.defer_scalar_refresh = true
    example.run
  ensure
    Rails.configuration.x.defer_scalar_refresh = false
  end

  let(:user) { create(:user) }
  let(:computer) { create(:computer, user: user) }
  let(:commit) { create(:commit) }
  let(:test_cases) { %w[pisn wd_aic make_co_wd].map { |n| create(:test_case, name: n, module: 'star') } }
  let!(:tccs) { test_cases.map { |tc| create(:test_case_commit, commit: commit, test_case: tc) } }

  def result(tcc, passed: true)
    sub = create(:submission, commit: commit, computer: computer, entire: false, empty: false)
    create(:test_instance, commit: commit, computer: computer, test_case: tcc.test_case,
                           test_case_commit: tcc, submission: sub, passed: passed)
  end

  it 'flags a burst of results and enqueues one refresh for the commit' do
    tccs.each { |tcc| result(tcc) }

    expect(enqueued_jobs.count { |j| j['job_class'] == 'CommitRefreshJob' }).to eq(1)
    expect(commit.reload.scalars_dirty).to be true
    expect(TestCaseCommit.where(commit: commit).pluck(:needs_refresh)).to all(be true)
    expect(commit.passed_count).to eq(0)
  end

  it 'refreshes the TCCs and then the commit, and clears the flags' do
    result(tccs[0])
    result(tccs[1], passed: false)
    perform_enqueued_jobs

    commit.reload
    expect(commit.scalars_dirty).to be false
    expect(TestCaseCommit.where(commit: commit).pluck(:needs_refresh)).to all(be false)
    expect(commit.passed_count).to eq(1)
    expect(commit.failed_count).to eq(1)
    expect(tccs[0].reload.submission_count).to eq(1)
  end

  it 'enqueues again for a result that lands after a run' do
    result(tccs[0])
    perform_enqueued_jobs
    result(tccs[1])

    expect(enqueued_jobs.count { |j| j['job_class'] == 'CommitRefreshJob' }).to eq(1)
    perform_enqueued_jobs
    expect(commit.reload.passed_count).to eq(2)
  end

  it 'puts the flags back when a refresh fails' do
    result(tccs[0])
    allow_any_instance_of(TestCaseCommit).to receive(:update_and_save_scalars).and_raise('boom')

    expect { described_class.perform_now(commit.id) }.to raise_error('boom')
    expect(commit.reload.scalars_dirty).to be true
    expect(tccs[0].reload.needs_refresh).to be true
  end

  it 'flags a deleted submission for refresh' do
    result(tccs[0])
    perform_enqueued_jobs
    expect(commit.reload.passed_count).to eq(1)

    Submission.where(commit: commit).destroy_all
    perform_enqueued_jobs
    expect(commit.reload.passed_count).to eq(0)
    expect(tccs[0].reload.submission_count).to eq(0)
  end

  it 'sweeps commits left flagged' do
    Commit.where(id: commit.id).update_all(scalars_dirty: true)
    expect { described_class.sweep_stale }.to have_enqueued_job(described_class).with(commit.id)
  end
end
