# Recompute stored checksum scalars after a change to the comparison
# rules in ChecksumComparison. `test_case_commits.checksum_count` and
# `status` are only refreshed when a submission lands, so old rows keep
# whatever the rules were at the time — 46 TCCs from 2021 were still
# flagged under the pre-resolution-exclusion rules when this task was
# written.
#
# Candidates are TCCs whose stored count says "mismatch" plus any TCC
# with more than one distinct checksum among passing instances (the
# only rows the new rules could newly flag). Everything else can't
# change. Also re-derives Commit#status for commits whose stored
# status predates "uniform failures outrank mixed".
#
#   bundle exec rake checksums:recompute
namespace :checksums do
  desc 'Recompute TCC checksum counts/status and affected commit status.'
  task recompute: :environment do
    flagged = TestCaseCommit.where('checksum_count > 1').pluck(:id)
    multi = TestInstance.where(passed: true)
                        .where.not(checksum: [nil, ''])
                        .group(:test_case_commit_id)
                        .having('COUNT(DISTINCT checksum) > 1')
                        .pluck(:test_case_commit_id)
    tcc_ids = (flagged + multi).compact.uniq
    puts "Recomputing #{tcc_ids.size} test case commit(s)..."

    changed_commit_ids = Set.new
    TestCaseCommit.where(id: tcc_ids).find_each do |tcc|
      before = [tcc.checksum_count, tcc.status]
      tcc.update_and_save_scalars
      changed_commit_ids << tcc.commit_id if [tcc.checksum_count, tcc.status] != before
    end

    stale_precedence = Commit.where('failed_count > 0 AND status = 3').pluck(:id)
    commit_ids = changed_commit_ids.to_a | stale_precedence
    puts "#{changed_commit_ids.size} commit(s) with changed TCCs, " \
         "#{stale_precedence.size} with stale fail/mixed precedence."

    Commit.where(id: commit_ids).find_each do |commit|
      commit.update_scalars
      commit.save!
    end
    puts 'Done.'
  end
end
