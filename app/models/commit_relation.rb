class CommitRelation < ApplicationRecord
  belongs_to :parent, class_name: 'Commit'
  belongs_to :child,  class_name: 'Commit'
end
