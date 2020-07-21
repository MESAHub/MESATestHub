class AddRestartPhotoToTestInstances < ActiveRecord::Migration[5.1]
  def change
    add_column :test_instances, :photo_checksum, :string
  end
end
