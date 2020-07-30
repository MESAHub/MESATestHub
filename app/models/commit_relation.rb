class CommitRelation < ApplicationRecord
  belongs_to :parent, class_name: 'Commit', foreign_key: 'parent_id'
  belongs_to :child, class_name: 'Commit', foreign_key: 'child_id'
end
