namespace :other do
  desc "Assign order to all commits in a branch."
  task :reorder_commits, [:branch_name] => :environment do |t, args|
    puts "args are #{args}"
    puts "Reordering commits for branch \"#{args[:branch_name]}\"."
    branch = Branch.find_by(name: args[:branch_name])
    if branch
      puts "found branch #{branch.name}"
      branch.api_reorder_all_commits
    else
      puts "Unable to locate branch: \"#{args.branch_name}\"."
    end
  end
end
