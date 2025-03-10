namespace :db do
    desc "Clean up commits that no longer belong to any branch"
    task cleanup_orphaned_commits: :environment do
      # Find commits that don't have any branch memberships
      orphaned_commits = Commit.left_joins(:branch_memberships)
                              .where(branch_memberships: { id: nil })
                              
      if orphaned_commits.any?
        puts "Found #{orphaned_commits.count} orphaned commits to clean up"
        
        # Delete associated data in the correct order to maintain referential integrity
        orphaned_commit_ids = orphaned_commits.pluck(:id)
        
        # Delete test case commits and related test instances
        test_case_commits = TestCaseCommit.where(commit_id: orphaned_commit_ids)
        test_case_commit_ids = test_case_commits.pluck(:id)
        
        # Delete test instances for these test case commits
        test_instances = TestInstance.where(test_case_commit_id: test_case_commit_ids)
        test_instance_ids = test_instances.pluck(:id)
        
        # Delete instance inlists and inlist data
        instance_inlists = InstanceInlist.where(test_instance_id: test_instance_ids)
        instance_inlist_ids = instance_inlists.pluck(:id)
        
        # Delete inlist data
        InlistDatum.where(instance_inlist_id: instance_inlist_ids).delete_all
        puts "Deleted associated inlist data"
        
        # Delete instance inlists
        instance_inlists.delete_all
        puts "Deleted #{instance_inlist_ids.count} instance inlists"
        
        # Delete test instances
        test_instances.delete_all
        puts "Deleted #{test_instance_ids.count} test instances"
        
        # Delete test case commits
        test_case_commits.delete_all
        puts "Deleted #{test_case_commit_ids.count} test case commits"
        
        # Delete submissions associated with these commits
        submissions = Submission.where(commit_id: orphaned_commit_ids)
        submissions.delete_all
        puts "Deleted #{submissions.count} submissions"
        
        # Finally, delete the orphaned commits
        orphaned_commits.delete_all
        puts "Deleted #{orphaned_commit_ids.count} orphaned commits"
      else
        puts "No orphaned commits found"
      end
    end
  end