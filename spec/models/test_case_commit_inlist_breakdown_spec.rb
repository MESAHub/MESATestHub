require 'rails_helper'

RSpec.describe TestCaseCommit, '#inlist_breakdown' do
  let(:commit) { create(:commit) }
  let(:test_case) { create(:test_case) }
  let(:tcc) { TestCaseCommit.create!(commit: commit, test_case: test_case) }

  def run(computer:, inlists:, passed: true, **attrs)
    sub = create(:submission, commit: commit, computer: computer)
    ti = create(:test_instance, commit: commit, computer: computer, test_case: test_case,
                                test_case_commit: tcc, submission: sub, passed: passed, **attrs)
    inlists.each_with_index do |(name, extra), i|
      ii = ti.instance_inlists.create!(inlist: name, order: i, steps: 10 * (i + 1), model_number: 100 + i)
      (extra || {}).each { |k, v| ii.inlist_data.create!(name: k, val: v) }
    end
    ti
  end

  it 'is nil for a single-inlist test' do
    run(computer: create(:computer), inlists: [['inlist_only_header']])
    expect(tcc.inlist_breakdown).to be_nil
  end

  it 'gives one row per run per inlist, marking skipped inlists and per-inlist data' do
    full = run(computer: create(:computer, name: 'full_box'), run_optional: true,
               inlists: [['inlist_setup_header'], ['inlist_extra_header', { 'max_T' => 7.5 }], ['inlist_final_header']])
    dflt = run(computer: create(:computer, name: 'dflt_box'),
               inlists: [['inlist_setup_header'], ['inlist_final_header']])

    b = tcc.inlist_breakdown
    expect(b[:inlists].map { |i| i[:label] }).to eq(%w[setup extra final])
    expect(b[:extra]['inlist_extra_header']).to eq(['max_T'])

    extra_rows = b[:rows]['inlist_extra_header']
    expect(extra_rows.find { |r| r[:instance_id] == full.id }).to include(steps: 20, extra: { 'max_T' => 7.5 }, passed: true)
    expect(extra_rows.find { |r| r[:instance_id] == dflt.id }).to include(missing: true)
  end

  it "fails an inlist when the run didn't reach the next one" do
    ti = run(computer: create(:computer), passed: false,
             inlists: [['inlist_setup_header'], ['inlist_final_header']])
    b = tcc.inlist_breakdown
    expect(b[:rows]['inlist_setup_header'].first).to include(passed: true)
    expect(b[:rows]['inlist_final_header'].first).to include(passed: false, instance_id: ti.id)
  end
end
