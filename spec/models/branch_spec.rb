require 'rails_helper'

RSpec.describe Branch, type: :model do
  # Behaviors specific to this file used to test nearby_test_case_commits'
  # nil-position handling — obsolete now that branch_memberships.position
  # is gone. Coverage of the rewritten nearby_test_case_commits lives in
  # branch_ordering_spec.rb. This file stays as a home for any future
  # general Branch specs.
end
