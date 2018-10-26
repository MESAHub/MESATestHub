namespace :db do
  desc "Ensure test cases, test instances, and test cases are all linked to a test case version."
  task fix_test_case_versions: :environment do
    to_fix = TestInstance.where(test_case_version_id: nil)
    puts "Updating all #{to_fix.count} test instances."
    # callbacks on save actually do everything automatically for us
    to_fix.each(&:save)
  end
end
