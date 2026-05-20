# Keep the test suite from hitting GitHub's API.
#
# Commit has `after_create :api_update_test_cases`, which fans out to
# `Commit.api.content(...)` once per MESA module. Every spec that creates a
# Commit (directly or via a factory) would otherwise burn API calls — and on
# CI, where there's no GIT_TOKEN, the runner blows through GitHub's 60/hour
# anonymous limit within the first dozen tests.
#
# Stub by default; specs that actually want to exercise the callback can
# `allow_any_instance_of(Commit).to receive(:api_update_test_cases).and_call_original`.
RSpec.configure do |config|
  config.before(:each) do
    allow_any_instance_of(Commit).to receive(:api_update_test_cases)
  end
end
