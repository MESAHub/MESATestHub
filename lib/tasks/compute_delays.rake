namespace :db do
  desc 'Compute delay times (time from commit to first failing test) and output to a file called delays.dat.'
  task compute_delays: :environment do
    counter = 0
    File.open('delays.dat', 'w') do |f|
      Commit.where(status: [1, 3]).each do |c|
        f.puts(c.test_instances.
                  where(passed: false).
                  order(created_at: :asc).
                  first.created_at - c.created_at)
      end
    end    
  end
end