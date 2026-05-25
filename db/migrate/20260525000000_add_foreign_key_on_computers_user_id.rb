class AddForeignKeyOnComputersUserId < ActiveRecord::Migration[8.0]
  # `computers.user_id` has always carried an index but no FK
  # constraint, so PostgreSQL never enforced that the user
  # actually existed. Coupled with the historic lack of
  # `dependent: :destroy` on `User has_many :computers`, deleting
  # a user silently orphaned every computer the user owned (and
  # the entire downstream cascade of submissions / test_instances
  # / instance_inlists / inlist_data they pointed at).
  #
  # The Rails-side fix lives on the User model — adding
  # `dependent: :destroy` so `@user.destroy` cascades correctly.
  # This migration is the belt-and-suspenders backstop: a real FK
  # with ON DELETE CASCADE so even a direct
  # `users.where(id: X).delete_all` (or a future bug that bypasses
  # the model callbacks) leaves no orphans behind.
  #
  # Before applying the constraint we have to clean up any
  # already-orphaned rows in production, otherwise FK validation
  # will reject the migration. The `delete_all` path on the
  # orphan scope skips Rails callbacks — that's the desired
  # behavior here, since the user they belonged to is already
  # gone and the standard cascade has nothing to refresh.
  def up
    say_with_time "Cleaning up any pre-existing orphan computers" do
      execute <<~SQL
        DELETE FROM computers
        WHERE user_id IS NOT NULL
          AND NOT EXISTS (
            SELECT 1 FROM users WHERE users.id = computers.user_id
          )
      SQL
    end

    add_foreign_key :computers, :users, on_delete: :cascade,
                                        validate: true
  end

  def down
    remove_foreign_key :computers, :users
  end
end
