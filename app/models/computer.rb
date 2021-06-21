class Computer < ApplicationRecord
  has_many :submissions, dependent: :destroy
  has_many :test_instances, through: :submissions, dependent: :destroy
  has_many :instance_inlists, through: :test_instances
  belongs_to :user
  validates_presence_of :name
  validates_uniqueness_of :name
  validates_presence_of :user_id
  validates_presence_of :platform

  def self.platforms
    %w[macOS linux]
  end

  validates_inclusion_of :platform, in: %w[macOS linux]

  def user_name
    user.name
  end

  def email
    user.email
  end

  def validate_user(creator)
    return if creator.admin? || (creator.id == user_id)
    errors.add(:user, 'must be current user unless you are an admin.')
  end

  def to_s
    self.name
  end
end
