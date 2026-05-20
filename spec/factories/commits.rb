FactoryBot.define do
  factory :commit do
    sequence(:sha) { |n| Digest::SHA1.hexdigest("commit-#{n}") }
    short_sha { sha[0, 7] }
    author { "Test Author" }
    author_email { "author@example.com" }
    message { "Test commit message" }
    commit_time { Time.current }
    github_url { "https://github.com/MESAHub/mesa/commit/#{sha}" }
  end
end
