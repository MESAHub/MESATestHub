class BranchMembership < ApplicationRecord
  belongs_to :branch
  belongs_to :commit
end
