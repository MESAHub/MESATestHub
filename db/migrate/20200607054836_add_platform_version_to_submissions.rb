class AddPlatformVersionToSubmissions < ActiveRecord::Migration[5.1]
  def change
    add_column :submissions, :platform_version, :string
  end
end
