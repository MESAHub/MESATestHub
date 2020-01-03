class Submission < ApplicationRecord
  belongs_to :commit
  belongs_to :computer
  has_many :test_instances
  has_many :test_case_commits, through: :test_instances
end
