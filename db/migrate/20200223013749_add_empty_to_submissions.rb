class AddEmptyToSubmissions < ActiveRecord::Migration[5.1]
  def change
    add_column :submissions, :empty, :bool, default: false
  end
end
