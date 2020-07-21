class ActuallyAddRestartPhotoToTestInstance < ActiveRecord::Migration[5.1]
  def change
    add_column :test_instances, :restart_photo, :string
  end
end
