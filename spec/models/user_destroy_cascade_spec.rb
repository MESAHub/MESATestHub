require 'rails_helper'

# Cascade coverage for `User#destroy`. The cascade chain is:
#
#   User
#    └─ has_many :computers, dependent: :destroy
#          └─ has_many :submissions, dependent: :destroy
#                ├─ before_destroy :remember_affected_tcc_ids, prepend: true
#                ├─ after_commit :update_commit  (refreshes TCC + commit scalars)
#                └─ has_many :test_instances, dependent: :destroy
#                      └─ has_many :instance_inlists, dependent: :destroy
#                            └─ has_many :inlist_data, dependent: :destroy
#
# This file proves three things:
#
# 1. All rows belonging to a destroyed user are wiped — no orphans
#    survive at any level of the chain.
# 2. The TCC + Commit aggregate scalars get refreshed for every
#    submission the user owned, so a destroy doesn't leave stale
#    `passed_count` / `submission_count` / `status` lying behind.
# 3. Other users' data is untouched.
#
# Production saves a Submission atomically with its test_instances
# inside a single transaction (see `SubmissionsController#create`),
# so `after_commit` fires once with everything in place. We mirror
# that here via a `create_submission_with_instances` helper rather
# than the straightforward `create(:submission)` +
# `create(:test_instance, submission: ...)` chain, which would fire
# `after_commit` before the instances exist and leave the baseline
# counts wrong for reasons unrelated to the destroy path. Same
# trick as `submission_destroy_cascade_spec`.
RSpec.describe 'User destroy → cascade + scalar refresh', type: :model do
  let(:commit)    { create(:commit) }
  let(:test_case) { create(:test_case) }
  let!(:tcc) { create(:test_case_commit, commit: commit, test_case: test_case) }

  def create_submission_with_instances(computer:, instance_traits: [], instance_attrs: {})
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

  describe 'cascade of dependent rows' do
    it 'wipes every row beneath the destroyed user' do
      user = create(:user)
      computer = create(:computer, user: user)
      sub = create_submission_with_instances(computer: computer)
      ti = sub.test_instances.first
      # InstanceInlist + InlistDatum factories carry stale attrs
      # from removed columns, so build them directly with the
      # attributes the schema actually has.
      ii = InstanceInlist.create!(test_instance: ti, inlist: "inlist_project",
                                  runtime_minutes: 1.5, steps: 100, retries: 0)
      ilid = InlistDatum.create!(instance_inlist: ii, name: "Teff", val: 5778.0)

      computer_id   = computer.id
      submission_id = sub.id
      ti_id         = ti.id
      ii_id         = ii.id
      ilid_id       = ilid.id

      user.destroy

      expect(User.where(id: user.id)).to be_empty
      expect(Computer.where(id: computer_id)).to be_empty
      expect(Submission.where(id: submission_id)).to be_empty
      expect(TestInstance.where(id: ti_id)).to be_empty
      expect(InstanceInlist.where(id: ii_id)).to be_empty
      expect(InlistDatum.where(id: ilid_id)).to be_empty
    end

    it 'leaves other users\' data alone' do
      victim    = create(:user)
      bystander = create(:user)
      v_comp = create(:computer, user: victim)
      b_comp = create(:computer, user: bystander)
      create_submission_with_instances(computer: v_comp)
      bystander_sub = create_submission_with_instances(computer: b_comp)

      victim.destroy

      expect(User.where(id: bystander.id)).to exist
      expect(Computer.where(id: b_comp.id)).to exist
      expect(Submission.where(id: bystander_sub.id)).to exist
      expect(bystander_sub.test_instances.count).to eq(1)
    end
  end

  describe 'TCC + Commit scalar refresh' do
    it 'resets the TCC + Commit to untested when the user owned the only submission' do
      user = create(:user)
      computer = create(:computer, user: user)
      create_submission_with_instances(computer: computer)
      tcc.reload
      commit.reload
      expect(tcc.submission_count).to eq(1)
      expect(tcc.passed_count).to eq(1)
      expect(tcc.status).to eq(0)              # passing
      expect(commit.passed_count).to eq(1)
      expect(commit.status).to eq(0)

      user.destroy

      tcc.reload
      commit.reload
      expect(tcc.submission_count).to eq(0)
      expect(tcc.passed_count).to eq(0)
      expect(tcc.status).to eq(-1)             # untested
      expect(commit.passed_count).to eq(0)
      expect(commit.untested_count).to eq(1)
      expect(commit.status).to eq(-1)
    end

    it 'recomputes scalars when the destroyed user owned only some of the submissions' do
      victim    = create(:user)
      bystander = create(:user)
      victim_comp    = create(:computer, user: victim)
      bystander_comp = create(:computer, user: bystander)
      create_submission_with_instances(computer: victim_comp)
      create_submission_with_instances(computer: bystander_comp)

      tcc.reload
      expect(tcc.submission_count).to eq(2)
      expect(tcc.passed_count).to eq(2)
      expect(tcc.computer_count).to eq(2)

      victim.destroy

      tcc.reload
      expect(tcc.submission_count).to eq(1)
      expect(tcc.passed_count).to eq(1)
      expect(tcc.computer_count).to eq(1)
      expect(tcc.status).to eq(0) # still passing — bystander's submission remains
    end

    it 'flips a previously-mixed TCC back to passing when the user owned the failing instance' do
      mixed_failer  = create(:user)
      mixed_passer  = create(:user)
      fail_comp = create(:computer, user: mixed_failer)
      pass_comp = create(:computer, user: mixed_passer)
      create_submission_with_instances(computer: fail_comp, instance_traits: [:failing])
      create_submission_with_instances(computer: pass_comp)

      tcc.reload
      expect(tcc.status).to eq(3) # mixed

      mixed_failer.destroy

      tcc.reload
      expect(tcc.status).to eq(0) # passing — only the passing instance remains
      expect(tcc.failed_count).to eq(0)
      expect(tcc.passed_count).to eq(1)
    end
  end

  describe 'users with no data' do
    it 'destroys cleanly even when the user has no computers' do
      user = create(:user)
      expect { user.destroy }.not_to raise_error
      expect(User.where(id: user.id)).to be_empty
    end

    it 'destroys cleanly when the user has computers but no submissions' do
      user = create(:user)
      computer = create(:computer, user: user)
      expect { user.destroy }.not_to raise_error
      expect(Computer.where(id: computer.id)).to be_empty
    end
  end

  describe 'DB-level foreign key' do
    # Belt-and-suspenders check: even if a future bug bypasses the
    # Rails-side `dependent: :destroy` (e.g. `delete_all` skipping
    # callbacks), the FK with ON DELETE CASCADE keeps the
    # computers table consistent.
    it 'cascades when the user is deleted at the DB level (bypassing callbacks)' do
      user = create(:user)
      computer = create(:computer, user: user)

      User.where(id: user.id).delete_all  # skips callbacks

      expect(Computer.where(id: computer.id)).to be_empty
    end
  end
end
