json.extract! commit, :id, :sha, :author, :author_email, :message,
              :commit_time, :created_at, :updated_at, :passed_count,
              :failed_count, :mixed_count, :untested_count, :checksum_count,
              :computer_count, :complete_computer_count, :status

branch = commit.branches.first
if branch
  json.url commit_url(branch.name, commit.short_sha, format: :json)
end
