namespace :db do
  desc "Generate cpu_hours for older data."
  task set_cpu_hours: :environment do
    unset_count  = TestInstance.where(cpu_hours: 0.0)
    puts "Updating #{[10_000, unset_count]} of #{unset_count} test instances."
    TestInstance.where(cpu_hours: 0.0).limit(10_000).each(&:update_cpu_hours)
  end
end
