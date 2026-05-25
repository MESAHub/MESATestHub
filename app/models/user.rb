class User < ApplicationRecord
  # Destroying a user cascades through computers → submissions →
  # test_instances → instance_inlists → inlist_data. The
  # Submission#before_destroy/after_commit pair refreshes affected
  # TestCaseCommit + Commit scalars so the destroy doesn't leave
  # stale counts behind. See user_destroy_cascade_spec for the
  # full coverage.
  has_many :computers, dependent: :destroy
  has_many :test_instances, through: :computers
  has_many :submissions, through: :computers

  validates_uniqueness_of :email
  validates_presence_of :name

  # do checks on password to make sure it is long enough when we change, but
  # doesn't complain when it is left blank and unchanged during an edit
  validates :password, presence: { on: create }, length: { minimum: 8 },
            :if => :password_digest_changed?

  has_secure_password

  def admin?
    admin
  end
end
