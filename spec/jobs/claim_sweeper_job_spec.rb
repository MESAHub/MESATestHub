require 'rails_helper'

RSpec.describe ClaimSweeperJob, type: :job do
  it 'delegates to Claim.sweep_expired!' do
    expect(Claim).to receive(:sweep_expired!)
    described_class.perform_now
  end
end
