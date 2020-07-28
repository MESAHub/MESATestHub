class Branch < ApplicationRecord
  has_one :head, class_name: 'Commit', foreign_key: 'head_id'
end
