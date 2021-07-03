class AddPositionToBranchMemberships < ActiveRecord::Migration[6.0]
  def change
    add_column :branch_memberships, :position, :integer
  end
end
