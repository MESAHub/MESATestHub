# A client-computed fingerprint of what a submission reports (a hash of
# the build's build.log, or of one test's testhub.yml), so re-sending the
# same result -- a retried `mesa_test submit`, a head node re-uploading
# what compute nodes already sent -- is recognized and ignored instead of
# stored twice. Unique per computer + commit; null for older clients.
class AddFingerprintToSubmissions < ActiveRecord::Migration[8.0]
  def change
    add_column :submissions, :fingerprint, :string
    add_index :submissions, %i[computer_id commit_id fingerprint], unique: true,
              where: 'fingerprint IS NOT NULL', name: 'index_submissions_on_computer_commit_fingerprint'
  end
end
