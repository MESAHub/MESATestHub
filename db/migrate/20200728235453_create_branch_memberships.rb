class CreateBranchMemberships < ActiveRecord::Migration[5.1]
  def change
    create_table :branch_memberships do |t|

      t.timestamps
    end
  end
end
