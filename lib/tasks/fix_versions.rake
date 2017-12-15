namespace :db do
  desc "Convert 'mesa_version' to proper foreign key."
  task fix_versions: :environment do
    puts "Updating all #{TestInstance.count} test instances."
    TestInstance.all.each(&:update_version)
  end

  desc "Convert 'version_added' to proper foreign key."
  task fix_version_added: :environment do
    puts "Updating all #{TestCase.count} test cases."
    TestCase.all.each(&:update_version_created)
  end
end
