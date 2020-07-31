class CommitRelation < ApplicationRecord
  belongs_to :parent, class_name: 'Commit', foreign_key: 'parent_id',
             counter_cache: :children_count
  belongs_to :child, class_name: 'Commit', foreign_key: 'child_id',
             counter_cache: :parents_count
end
