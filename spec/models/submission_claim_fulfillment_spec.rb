require 'rails_helper'

# Submission#fulfill_claims (docs/dispatcher-and-claims.md,
# "Fulfillment"): a submission answers the claims its computer holds
# on its commit, with or without naming a claim id.
RSpec.describe Submission, 'claim fulfillment' do
  let(:computer) { create(:computer) }
  let(:commit)   { create(:commit) }
  let(:tcc_a)    { create(:test_case_commit, commit: commit) }
  let(:tcc_b)    { create(:test_case_commit, commit: commit) }

  def submit!(instances_for: [], on: computer, **attrs)
    sub = Submission.new(commit: commit, computer: on, entire: false,
                         empty: instances_for.empty?, compiled: true, **attrs)
    instances_for.each do |tcc|
      sub.test_instances.build(attributes_for(:test_instance).merge(
        commit: commit, computer: on, test_case: tcc.test_case
      ))
    end
    sub.save!
    sub
  end

  it 'fulfills build claims with a build-only submission, leaving test claims open' do
    build = create(:claim, computer: computer, commit: commit)
    test  = create(:claim, :test_scope, computer: computer, commit: commit, test_case_commit: tcc_a)

    submit!

    expect(build.reload.status).to eq('fulfilled')
    expect(test.reload.status).to eq('pending')
  end

  it 'fulfills only the test claims whose tests it carries, plus build claims' do
    build = create(:claim, computer: computer, commit: commit)
    a = create(:claim, :test_scope, computer: computer, commit: commit, test_case_commit: tcc_a)
    b = create(:claim, :test_scope, computer: computer, commit: commit, test_case_commit: tcc_b)

    submit!(instances_for: [tcc_a])

    expect([build, a, b].map { |c| c.reload.status }).to eq(%w[fulfilled fulfilled pending])
  end

  it 'reactivates expired claims (late results)' do
    late = create(:claim, :expired, computer: computer, commit: commit)
    submit!
    expect(late.reload.status).to eq('fulfilled')
  end

  it "leaves other computers' claims and other commits' claims alone" do
    theirs = create(:claim, computer: create(:computer), commit: commit)
    elsewhere = create(:claim, computer: computer, commit: create(:commit))

    submit!

    expect(theirs.reload.status).to eq('pending')
    expect(elsewhere.reload.status).to eq('pending')
  end

  it 'still honors an explicit claim id' do
    named = create(:claim, computer: computer, commit: create(:commit))
    submit!(claim: named)
    expect(named.reload.status).to eq('fulfilled')
  end
end
