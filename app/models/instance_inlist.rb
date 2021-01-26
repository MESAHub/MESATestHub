class InstanceInlist < ApplicationRecord
  belongs_to :test_instance
  has_many :inlist_data, dependent: :destroy
  default_scope { order(order: :asc) }
end
