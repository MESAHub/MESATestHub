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

  desc "Change null compilers to 'SDK' and update versions."
  task fix_compilers_and_versions: :environment do
    TestInstance.where(compiler: nil, version_id: nil).each do |ti|
      ti.compiler = 'SDK'
      ti.version ||= Version.find_or_create_by(number: ti.mesa_version)
      ti.save!
    end
  end
end
