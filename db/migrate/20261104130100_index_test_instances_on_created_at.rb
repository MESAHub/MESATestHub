# MorningReport#load_commits finds the day's results by
# test_instances.created_at, which had no index: every digest (twice a
# day, plus previews) scanned the whole table, ~4.8s on average and up to
# 17s in production, pushing useful pages out of Postgres's cache.
# Built concurrently so submissions keep writing while it builds.
class IndexTestInstancesOnCreatedAt < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :test_instances, :created_at, algorithm: :concurrently, if_not_exists: true
  end
end
