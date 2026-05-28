class Computer < ApplicationRecord
  has_many :submissions, dependent: :destroy
  has_many :test_instances, through: :submissions, dependent: :destroy
  has_many :instance_inlists, through: :test_instances
  has_many :claims, dependent: :destroy
  belongs_to :user
  validates_presence_of :name
  validates_uniqueness_of :name
  validates_presence_of :user_id
  validates_presence_of :platform

  SORT_OPTIONS = %w[recent name maintainer].freeze

  # Sort the relation by one of the canonical orderings used on
  # `computers#index`. Falls back to `:recent` for anything
  # unrecognized so a stale URL can't pin an undefined sort.
  #
  # `:recent`     last-submission-time descending, then computer name
  #               (a correlated subquery so Kaminari's count() pass
  #               isn't fighting a GROUP BY in the outer relation)
  # `:name`       computer name ascending (case-insensitive)
  # `:maintainer` user's last name (last whitespace-separated token)
  #               ascending, with computer name as the tiebreaker —
  #               needs the user join to be in scope; the controller
  #               only exposes this on the admin all-users view
  scope :ordered, ->(sort) {
    case sort.to_s
    when "name"
      order(Arel.sql("LOWER(computers.name) ASC"))
    when "maintainer"
      joins(:user).order(
        Arel.sql("LOWER(regexp_replace(users.name, '.* ', '')) ASC, " \
                 "LOWER(computers.name) ASC")
      )
    else
      order(
        Arel.sql("(SELECT MAX(submissions.created_at) FROM submissions " \
                 "WHERE submissions.computer_id = computers.id) DESC NULLS LAST, " \
                 "LOWER(computers.name) ASC")
      )
    end
  }

  PLATFORMS = %w[macOS linux].freeze
  validates_inclusion_of :platform, in: PLATFORMS

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
