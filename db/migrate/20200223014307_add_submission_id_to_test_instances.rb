class AddSubmissionIdToTestInstances < ActiveRecord::Migration[5.1]
  def change
    add_reference :test_instances, :submission
  end
end
