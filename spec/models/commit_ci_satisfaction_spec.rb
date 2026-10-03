require 'rails_helper'

# Phase C: Commit#refresh_ci_satisfaction! and the Submission callback
# that drives it (docs/dispatcher-and-claims.md, "Configurations").
RSpec.describe 'Commit CI-request satisfaction' do
  let(:commit) { create(:commit, wants_full_inlists: true, wants_fpe: true, wants_converge: true) }
  let!(:tccs) { create_list(:test_case_commit, 2, commit: commit) }
  let(:alpha) { create(:computer) }
  let(:beta)  { create(:computer) }

  # One per-test submission, as current clients send them.
  def run!(tcc, on:, **attrs)
    sub = Submission.new(commit: commit, computer: on, entire: false, empty: false)
    sub.test_instances.build(attributes_for(:test_instance).merge(
      commit: commit, computer: on, test_case: tcc.test_case, **attrs
    ))
    sub.save!
  end

  it 'is met once one computer has a full-inlists run of every test, pass or fail' do
    run!(tccs[0], on: alpha, run_optional: true)
    expect(commit.reload.full_inlists_satisfied_at).to be_nil

    run!(tccs[1], on: alpha, run_optional: true, passed: false)
    expect(commit.reload.full_inlists_satisfied_at).to be_present
    expect(commit.fpe_satisfied_at).to be_nil
  end

  it 'does not pool partial coverage across computers' do
    run!(tccs[0], on: alpha, fpe_checks: true)
    run!(tccs[1], on: beta, fpe_checks: true)
    expect(commit.reload.fpe_satisfied_at).to be_nil
  end

  it 'reads converge from a non-default resolution_factor' do
    run!(tccs[0], on: alpha, resolution_factor: 0.8)
    run!(tccs[1], on: alpha, resolution_factor: 0.8)
    expect(commit.reload.converge_satisfied_at).to be_present
  end

  it 'ignores default runs and leaves unflagged commits alone' do
    plain = create(:commit)
    create(:test_case_commit, commit: plain)
    expect { plain.refresh_ci_satisfaction! }.not_to(change { plain.reload.attributes })

    tccs.each { |tcc| run!(tcc, on: alpha) }
    expect(commit.reload.full_inlists_satisfied_at).to be_nil
  end

  it 'never moves a stamp once set' do
    stamp = 3.days.ago.change(usec: 0)
    commit.update_columns(full_inlists_satisfied_at: stamp)
    tccs.each { |tcc| run!(tcc, on: alpha, run_optional: true) }
    expect(commit.reload.full_inlists_satisfied_at).to eq(stamp)
  end
end
