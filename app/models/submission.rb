class Submission < ApplicationRecord
  belongs_to :commit
  belongs_to :computer
  has_one :user, through: :computer

  # deleting the submission deletes all associated test instances
  has_many :test_instances, dependent: :destroy
  has_many :test_case_commits, through: :test_instances

  after_commit :update_commit

  paginates_per 25


  # syntactic sugar to determine if the submission is empty
  def empty?
    empty
  end

  # syntactic sugar to determine if the submission is entire
  def entire?
    entire
  end

  # text used when identifying computer in various context. This can change
  # when software is updated on the computer
  def computer_specification
    spec = ''
    spec += computer.platform + ' ' if computer.platform
    spec += platform_version + ' ' if platform_version
    if sdk_version
      spec += "SDK #{sdk_version} "
      spec += "#{math_backend} " if math_backend
    else
      spec += compiler + ' ' if compiler
      spec += compiler_version if compiler_version
    end
    spec = 'no specificaiton' if spec.empty?
    spec.strip
  end

  private

  # do this whenever we change submissions so the commit stays up to date
  def update_commit
    commit.update_scalars
    commit.save
    test_case_commits.each { |tcc| tcc.update_and_save_scalars }
  end

end
