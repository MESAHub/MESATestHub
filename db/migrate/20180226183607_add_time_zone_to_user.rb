class AddTimeZoneToUser < ActiveRecord::Migration[5.1]
  def up
    add_column :users, :time_zone, :string,
               default: 'Pacific Time (US & Canada)'
  end
  def down
    remove_column :user, :time_zone
  end
end
