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

  # ---------------------------------------------------------- API keys
  #
  # One key per computer (docs/api-keys.md). mesa_test sends it as
  # `Authorization: Bearer <key>`; the key alone identifies the
  # computer, and through it the user. Only a SHA-256 digest is
  # stored — the key is 32 random bytes, so a fast hash is safe and
  # lookup is a single indexed equality match, no per-request bcrypt.
  API_KEY_PREFIX = 'mth_'.freeze
  # Don't write `api_key_last_used_at` on every one of a run's
  # hundreds of submissions.
  API_KEY_TOUCH_INTERVAL = 5.minutes

  def self.api_key_digest(key)
    Digest::SHA256.hexdigest(key.to_s)
  end

  # The computer a key belongs to, or nil.
  def self.find_by_api_key(key)
    return nil unless key.to_s.start_with?(API_KEY_PREFIX)
    find_by(api_key_digest: api_key_digest(key))
  end

  # Replace any existing key with a fresh one and return the plaintext.
  # This is the only time the plaintext exists server-side.
  def generate_api_key!
    key = API_KEY_PREFIX + SecureRandom.urlsafe_base64(32)
    update_columns(api_key_digest: self.class.api_key_digest(key),
                   api_key_prefix: key[0, API_KEY_PREFIX.length + 6],
                   api_key_created_at: Time.current,
                   api_key_last_used_at: nil)
    key
  end

  def revoke_api_key!
    update_columns(api_key_digest: nil, api_key_prefix: nil,
                   api_key_created_at: nil, api_key_last_used_at: nil)
  end

  def api_key?
    api_key_digest.present?
  end

  def touch_api_key_last_used!(now = Time.current)
    return if api_key_last_used_at && api_key_last_used_at > now - API_KEY_TOUCH_INTERVAL
    update_columns(api_key_last_used_at: now)
  end
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
