desc 'Seek out new pull requests and add to database.'
task update_pulls: :environment do
  Commit.api_update_pulls
end
