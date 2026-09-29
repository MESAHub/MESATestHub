# Number of inlists an instance actually ran. Checksum comparison
# groups instances by this rather than by `run_optional`: a test with
# no optional inlists runs the same inlists either way, so a "full"
# run of it is directly comparable to a default run, and two full runs
# of a test that *does* have optional inlists are comparable to each
# other. Stored (rather than counted on the fly) so commits#show can
# group checksums from the already-loaded test_instances without
# eager-loading every instance_inlist row.
class AddInlistCountToTestInstances < ActiveRecord::Migration[8.0]
  def up
    add_column :test_instances, :inlist_count, :integer

    execute <<~SQL
      UPDATE test_instances ti
      SET inlist_count = counts.n
      FROM (
        SELECT test_instance_id, COUNT(*) AS n
        FROM instance_inlists
        GROUP BY test_instance_id
      ) counts
      WHERE counts.test_instance_id = ti.id
    SQL
  end

  def down
    remove_column :test_instances, :inlist_count
  end
end
