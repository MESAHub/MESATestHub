class CommitRelation < ApplicationRecord
  belongs_to :parent, class_name: 'Commit'
  belongs_to :child,  class_name: 'Commit'

  # Bulk inserts (Commit.ingest_payload_edges) correct times themselves.
  after_create { Commit.correct_times_from([child_id]) }
end
