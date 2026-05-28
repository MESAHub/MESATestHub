require 'rails_helper'

RSpec.describe MorningMailerJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  let(:message) { instance_double(ActionMailer::MessageDelivery) }

  before { allow(MorningMailer).to receive(:daily).and_return(message) }

  # 2026-05-28 is EDT (UTC-4), so 8 AM Eastern is 12:00 UTC.
  let(:eight_am_eastern) { Time.utc(2026, 5, 28, 12, 30) }
  let(:one_pm_eastern)   { Time.utc(2026, 5, 28, 17, 30) }

  context 'when the local clock reads 8 AM Eastern' do
    it 'enqueues the digest' do
      travel_to eight_am_eastern do
        expect(message).to receive(:deliver_later)
        described_class.perform_now
      end
    end
  end

  context 'when the local clock is not 8 AM Eastern' do
    it 'short-circuits without delivering' do
      travel_to one_pm_eastern do
        expect(MorningMailer).not_to receive(:daily)
        described_class.perform_now
      end
    end

    it 'delivers anyway when forced' do
      travel_to one_pm_eastern do
        expect(message).to receive(:deliver_later)
        described_class.perform_now(force: true)
      end
    end
  end
end
