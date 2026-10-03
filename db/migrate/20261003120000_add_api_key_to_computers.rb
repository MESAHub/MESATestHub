# Per-computer API keys (docs/api-keys.md). Only a SHA-256 digest of
# the key is stored; the plaintext is shown once at generation time.
# The prefix is the key's first few characters, kept so the computer
# page can say which key is active without being able to reproduce it.
class AddApiKeyToComputers < ActiveRecord::Migration[8.0]
  def change
    add_column :computers, :api_key_digest, :string
    add_column :computers, :api_key_prefix, :string
    add_column :computers, :api_key_created_at, :datetime
    add_column :computers, :api_key_last_used_at, :datetime
    add_index :computers, :api_key_digest, unique: true
  end
end
