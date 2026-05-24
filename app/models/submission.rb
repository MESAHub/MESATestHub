class Submission < ApplicationRecord
  belongs_to :commit
  belongs_to :computer
  has_one :user, through: :computer

  # deleting the submission deletes all associated test instances
  has_many :test_instances, dependent: :destroy
  has_many :test_case_commits, through: :test_instances

  after_commit :update_commit

  paginates_per 25

  # Inclusive of both endpoints. Either bound is optional — pass nil
  # to leave that end open. Used by the computers#show submissions
  # toolbar so users can narrow down a bad batch by submission time
  # before deleting.
  scope :submitted_between, ->(from, to) {
    scope = all
    scope = scope.where("submissions.created_at >= ?", from) if from
    scope = scope.where("submissions.created_at <= ?", to) if to
    scope
  }

  # Prefix-match a (partial) commit SHA — accepts 4+ characters so
  # the typical short-SHA paste (`abc1234`) works without forcing
  # the full 40-character hex. Lowercased for case-insensitive
  # match (SHAs are stored lowercase).
  scope :for_commit_sha, ->(sha) {
    sha = sha.to_s.strip.downcase
    return all if sha.blank?
    joins(:commit).where("commits.sha LIKE ?", "#{sha}%")
  }

  # Three operational categories of submission, mapped onto the
  # `empty` + `entire` boolean pair stored on the row:
  #
  #   empty       — build status only, no test instances.
  #                 `empty = true`
  #   individual  — a single (or small) batch of test instances,
  #                 not the whole suite. `empty = false AND
  #                 entire = false`
  #   combined    — build status + the entire test suite in one
  #                 submission. `entire = true`
  #
  # Production data confirms these three states partition the
  # table (no `(true, true)` or NULL rows in 843k submissions).
  TYPES = %w[empty individual combined].freeze

  scope :of_type, ->(type) {
    case type.to_s
    when "empty"
      where(empty: true)
    when "individual"
      where(empty: false, entire: false)
    when "combined"
      where(entire: true)
    else
      all
    end
  }


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
