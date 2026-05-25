# Composite index that backs the `Computer.ordered(:recent)` scope
# used by `computers#index` + `#index_all`. The view sorts computers
# by their most-recent submission via a correlated subquery
#
#   ORDER BY (SELECT MAX(submissions.created_at)
#             FROM submissions
#             WHERE submissions.computer_id = computers.id) DESC
#
# Without a composite index, each computer scans every matching
# submission row (the existing `index_submissions_on_computer_id`
# narrows by computer but Postgres still has to walk each match to
# find the max created_at). On the ~850k-row prod submissions
# table that scan was ~400ms total across 44 computers. With this
# composite, Postgres uses an index-only scan that picks the
# greatest `created_at` per `computer_id` in single-digit ms.
#
# Built with `algorithm: :concurrently` so adding the index on prod
# doesn't block submission writes — the submissions table is on
# the hot path of every test_client POST.
class AddComputerIdAndCreatedAtIndexToSubmissions < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :submissions, [:computer_id, :created_at],
              name: "index_submissions_on_computer_id_and_created_at",
              algorithm: :concurrently
  end
end
