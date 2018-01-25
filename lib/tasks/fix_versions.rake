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

  desc "Convert 'mesa_version' to proper foreign key if not already done."
  task fix_broken_versions: :environment do
    TestInstance.where(version_id: nil).each(&:update_version)
  end

  desc "Change null compilers to 'SDK'"
  task fix_sdks: :environment do
    TestInstance.where(compiler: nil).each do |ti|
      ti.update_attributes!(compiler: 'SDK')
    end
  end
end
