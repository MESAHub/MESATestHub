class RenamePhotoChecksumToRestartChecksumInInstance < ActiveRecord::Migration[5.1]
  def change
    rename_column :test_instances, :photo_checksum, :restart_checksum
  end
end
