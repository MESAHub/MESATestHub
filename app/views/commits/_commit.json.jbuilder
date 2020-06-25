json.extract! commit, :id, :sha, :author, :author_email, :message,
              :commit_time, :created_at, :updated_at, :passed_count,
              :failed_count, :mixed_count, :untested_count, :checksum_count,
              :computer_count, :complete_computer_count, :status
json.url commit_url(commit.branches[0], commit, format: json)