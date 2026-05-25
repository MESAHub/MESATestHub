require 'rails_helper'

# Trace what happens to aggregate state when a Submission is
# destroyed (the path the bulk-delete UI on computers#show now
# exposes to maintainers). The model has two layers of derived
# scalars — TestCaseCommit columns (`status`, `passed_count`,
# `submission_count`, `computer_count`, `checksum_count`,
# `last_tested`) and Commit columns (`passed_count`,
# `failed_count`, `mixed_count`, `checksum_count`,
# `untested_count`, `status`) — and both need to stay coherent
# with the underlying test_instances rows. Without the
# refresh-by-id pass in `Submission#update_commit` these scalars
# end up lying after a delete, which corrupts the
# computers#show + commits#show readings.
#
# Production saves a Submission atomically with its
# test_instances inside a single transaction (see
# `SubmissionsController#create`), so `after_commit` fires once
# with everything in place. We mirror that here via a small
# `create_submission_with_instances` helper rather than the
# straightforward `create(:submission)` + `create(:test_instance,
# submission: ...)` chain, which would fire `after_commit`
# before the instances exist and leave the baseline counts wrong
# for reasons unrelated to the destroy path.
RSpec.describe 'Submission destroy → TCC + Commit scalar refresh', type: :model do
  let(:commit)    { create(:commit) }
  let(:computer)  { create(:computer) }
  let(:test_case) { create(:test_case) }
  let!(:tcc) { create(:test_case_commit, commit: commit, test_case: test_case) }

  def create_submission_with_instances(instance_traits: [], instance_attrs: {})
    sub = Submission.new(
      commit: commit, computer: computer,
      compiled: true, entire: false, empty: false,
      compiler: 'gfortran', compiler_version: '12.2',
      sdk_version: '26.3.2', math_backend: 'OpenBLAS',
      platform_version: 'linux x86_64'
    )
    sub.test_instances.build(
      attributes_for(:test_instance, *instance_traits).merge(
        commit: commit, computer: computer,
        test_case: test_case, test_case_commit: tcc,
        checksum: 'abc1234'
      ).merge(instance_attrs)
    )
    sub.save!
    sub
  end

  describe 'TCC scalars' do
    it 'resets a TCC to untested when its only submission is destroyed' do
      sub = create_submission_with_instances
      tcc.reload
      expect(tcc.submission_count).to eq(1)
      expect(tcc.passed_count).to eq(1)
      expect(tcc.status).to eq(0) # :passing

      sub.destroy

      tcc.reload
      expect(tcc.submission_count).to eq(0)
      expect(tcc.passed_count).to eq(0)
      expect(tcc.failed_count).to eq(0)
      expect(tcc.computer_count).to eq(0)
      expect(tcc.checksum_count).to eq(0)
      expect(tcc.status).to eq(-1) # :untested
      expect(tcc.last_tested).to be_nil
    end

    it 'recomputes the TCC when one of several submissions is destroyed' do
      sub_a = create_submission_with_instances
      sub_b = create_submission_with_instances
      tcc.reload
      expect(tcc.submission_count).to eq(2)
      expect(tcc.passed_count).to eq(2)

      sub_a.destroy

      tcc.reload
      expect(tcc.submission_count).to eq(1)
      expect(tcc.passed_count).to eq(1)
      expect(tcc.status).to eq(0) # still passing
    end

    it 'flips a previously-mixed TCC back to passing when the failing instance is removed' do
      create_submission_with_instances
      failing_sub = create_submission_with_instances(instance_traits: [:failing])

      tcc.reload
      expect(tcc.status).to eq(3) # :mixed (one passed, one failed)

      failing_sub.destroy

      tcc.reload
      expect(tcc.status).to eq(0) # :passing — only the passing instance remains
      expect(tcc.failed_count).to eq(0)
      expect(tcc.passed_count).to eq(1)
    end
  end

  describe 'Commit scalars' do
    it 'recounts commit-level passed_count / untested_count / status when a sub is destroyed' do
      sub = create_submission_with_instances
      commit.reload
      expect(commit.passed_count).to eq(1)
      expect(commit.untested_count).to eq(0)
      expect(commit.status).to eq(0) # passing

      sub.destroy

      commit.reload
      expect(commit.passed_count).to eq(0)
      expect(commit.untested_count).to eq(1)
      expect(commit.status).to eq(-1) # untested — the only TCC is now untested
    end
  end

  describe 'empty submissions (no test instances)' do
    it 'destroys cleanly without touching TCC scalars' do
      empty_sub = create(:submission,
                         commit: commit, computer: computer,
                         empty: true, entire: false, compiled: false)
      tcc.reload
      baseline = tcc.attributes.slice('status', 'passed_count', 'failed_count',
                                       'submission_count', 'computer_count',
                                       'checksum_count', 'last_tested')
      empty_sub.destroy
      tcc.reload
      after = tcc.attributes.slice('status', 'passed_count', 'failed_count',
                                    'submission_count', 'computer_count',
                                    'checksum_count', 'last_tested')
      expect(after).to eq(baseline)
    end
  end

  describe 'cascading delete of test_instances' do
    it 'removes all test_instances when their submission is destroyed' do
      sub = create_submission_with_instances
      ti_ids = sub.test_instances.pluck(:id)
      expect(ti_ids.size).to eq(1)

      sub.destroy

      expect(TestInstance.where(id: ti_ids).count).to eq(0)
    end
  end
end
