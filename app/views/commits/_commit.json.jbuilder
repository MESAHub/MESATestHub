json.extract! commit, :id, :sha, :author, :author_email, :message,
              :commit_time, :created_at, :updated_at
json.url commit_url(commit.branch_names[0], commit, format: json)