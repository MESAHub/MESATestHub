class CreateBranchMemberships < ActiveRecord::Migration[5.1]
  def change
    create_table :branch_memberships do |t|
      t.references :branch
      t.references :commit
    end
  end
end
