class Submission < ApplicationRecord
  belongs_to :commit
  belongs_to :computer

  # deleting the submission deletes all associated test instances
  has_many :test_instances, dependent: :destroy
  
  has_many :test_case_commits, through: :test_instances
end
