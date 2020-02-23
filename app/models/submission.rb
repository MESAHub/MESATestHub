class Submission < ApplicationRecord
  belongs_to :commit
  belongs_to :computer

  # deleting the submission deletes all associated test instances
  has_many :test_instances, dependent: :destroy
  has_many :test_case_commits, through: :test_instances

  # syntactic sugar
  def empty?
    empty
  end

  def entire?
    entire
  end
end
