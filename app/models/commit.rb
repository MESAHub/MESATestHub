class Commit < ApplicationRecord
  has_many :submissions
  has_many :test_case_commits
  has_many :test_cases, through: :test_case_commits
  has_many :computers, through: :submissions

  validates_uniqueness_of :sha
  validates_presence_of :author, :author_email, :message, :commit_datetime

  def <=>(commit_1, commit_2)
    # sort commits according to their datetimes, with recent commits FIRST
    commit_2.commit_datetime <=> commit_1.commit_datetime
  end
end
