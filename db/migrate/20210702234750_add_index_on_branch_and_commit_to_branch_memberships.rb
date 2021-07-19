class AddIndexOnBranchAndCommitToBranchMemberships < ActiveRecord::Migration[6.0]
  def change
    add_index(:branch_memberships, [:commit_id, :branch_id], unique: true)
  end
end
