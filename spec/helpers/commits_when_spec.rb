require 'rails_helper'

RSpec.describe CommitsHelper, type: :helper do
  let(:anchor) { Time.zone.local(2026, 9, 4, 23, 59, 59) }

  describe '#commit_when_label' do
    it 'reads as an age when measured from now' do
      expect(helper.commit_when_label(3.hours.ago, anchor: Time.current, mode: :now)).to eq('3h ago')
    end

    it 'reads as an offset before a picked date' do
      expect(helper.commit_when_label(anchor - 2.days, anchor: anchor, mode: :date)).to eq('−2d')
    end

    it "never says 'now' relative to a picked date" do
      expect(helper.commit_when_label(anchor - 10.seconds, anchor: anchor, mode: :date)).to eq('<1m')
    end
  end

  describe '#commit_when_header' do
    it 'names the picked day' do
      expect(helper.commit_when_header(anchor: anchor, mode: :date)).to eq('Before Sep 4')
      expect(helper.commit_when_header(anchor: anchor, mode: :now)).to eq('When')
    end
  end

  describe '#group_commits_by_age' do
    it 'uses present-tense labels when measured from now' do
      c = build_stubbed(:commit, commit_time: 1.hour.ago)
      expect(helper.group_commits_by_age([c], now: Time.current, mode: :now).map { |_, label, _| label }).to eq(['Today'])
      expect(helper.group_commits_by_age([c], now: Time.current, mode: :date).map { |_, label, _| label }).to eq(['Same day'])
    end
  end
end
