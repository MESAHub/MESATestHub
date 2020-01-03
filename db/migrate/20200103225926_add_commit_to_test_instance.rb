class AddCommitToTestInstance < ActiveRecord::Migration[5.1]
  def change
    add_reference :test_instances, :commit, index: true
  end
end
