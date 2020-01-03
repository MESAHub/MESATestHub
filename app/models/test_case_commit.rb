class TestCaseCommit < ApplicationRecord
  belongs_to :commit
  belongs_to :test_case
  has_many :test_instances
  has_many :submissions, through: :test_instances
end
