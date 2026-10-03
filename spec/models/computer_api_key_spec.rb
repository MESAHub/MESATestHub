require 'rails_helper'

# Per-computer API keys (docs/api-keys.md): generation, lookup,
# revocation, and the throttled last-used stamp.
RSpec.describe Computer, 'API keys' do
  let(:computer) { create(:computer) }

  it 'generates a prefixed key and stores only its digest' do
    key = computer.generate_api_key!

    expect(key).to start_with('mth_')
    expect(key.length).to be > 40
    computer.reload
    expect(computer.api_key?).to be true
    expect(computer.api_key_digest).to eq(Digest::SHA256.hexdigest(key))
    expect(computer.api_key_prefix).to eq(key[0, 10])
    expect(computer.api_key_created_at).to be_within(5.seconds).of(Time.current)
    expect(computer.attributes.values).not_to include(key)
  end

  it 'finds the computer by key, and nothing for unknown or unprefixed keys' do
    key = computer.generate_api_key!

    expect(Computer.find_by_api_key(key)).to eq(computer)
    expect(Computer.find_by_api_key("#{key}x")).to be_nil
    expect(Computer.find_by_api_key(key.delete_prefix('mth_'))).to be_nil
    expect(Computer.find_by_api_key(nil)).to be_nil
  end

  it 'invalidates the old key when a new one is generated' do
    old_key = computer.generate_api_key!
    new_key = computer.generate_api_key!

    expect(Computer.find_by_api_key(old_key)).to be_nil
    expect(Computer.find_by_api_key(new_key)).to eq(computer)
  end

  it 'revokes the key' do
    key = computer.generate_api_key!
    computer.revoke_api_key!

    expect(Computer.find_by_api_key(key)).to be_nil
    expect(computer.reload.api_key?).to be false
  end

  it 'stamps last use at most every few minutes' do
    computer.generate_api_key!
    t0 = Time.current.change(usec: 0)
    computer.touch_api_key_last_used!(t0)
    computer.touch_api_key_last_used!(t0 + 1.minute)
    expect(computer.reload.api_key_last_used_at).to eq(t0)

    computer.touch_api_key_last_used!(t0 + 10.minutes)
    expect(computer.reload.api_key_last_used_at).to eq(t0 + 10.minutes)
  end
end
