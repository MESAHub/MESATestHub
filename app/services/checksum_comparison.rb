# Decides which of a test_case_commit's instances are expected to agree
# bit-for-bit, and which of them don't.
#
# Only passing instances that carry a real checksum take part, and
# they're only compared against instances run the same way:
#
#   * same number of inlists run (a run that skipped optional inlists
#     ends on a different model than one that ran them all), and
#   * same toolchain class — MESA SDK vs. anything else. SDK versions
#     are expected to agree with each other; a hand-tuned ifort build
#     isn't expected to agree with the SDK.
#
# Excluded outright:
#
#   * FPE-checking runs — whether trapping builds should reproduce
#     normal builds bit-for-bit is unsettled, so they don't vote.
#   * non-standard resolution (resolution_factor != 1) — changes the
#     answer by design.
#   * the all-zeros placeholder MESA's test suite writes for tests
#     marked `.ignore_checksum`.
#
# Within a group, the plurality checksum (by distinct computer) is the
# consensus; instances carrying any other checksum "disagree". If no
# checksum has a strict plurality, every instance in the group
# disagrees — there's no way to say who's right.
class ChecksumComparison
  PLACEHOLDER_CHECKSUM = ('0' * 32).freeze

  # Columns needed to build a comparison without loading full rows.
  COLUMNS = %i[id computer_id passed checksum fpe_checks resolution_factor
               inlist_count run_optional sdk_version].freeze

  def self.key_for(instance)
    return nil unless instance.passed
    checksum = instance.checksum
    return nil if checksum.blank? || checksum == PLACEHOLDER_CHECKSUM
    return nil if instance.fpe_checks
    factor = instance.resolution_factor
    return nil unless factor.nil? || (factor - 1.0).abs < 1e-6

    # Pre-migration rows that never got an inlist_count fall back to
    # the coarser run_optional split rather than pooling with
    # everything else.
    inlists = instance.inlist_count || (instance.run_optional ? :full : :default)
    [inlists, instance.sdk_version.present?]
  end

  def initialize(instances)
    @groups = instances.group_by { |i| self.class.key_for(i) }
    @groups.delete(nil)
  end

  # Largest number of distinct checksums inside any one comparison
  # group. 0 when nothing is comparable, 1 when everything agrees,
  # > 1 when reproducibility is broken. Stored as
  # TestCaseCommit#checksum_count.
  def max_distinct
    @max_distinct ||= @groups.values.map { |g| g.map(&:checksum).uniq.size }.max || 0
  end

  def mismatch?
    max_distinct > 1
  end

  def disagrees?(instance)
    disagreeing_ids.include?(instance.id)
  end

  # Checksums involved in a disagreement, for the "checksums seen"
  # line on the test-on-commit page.
  def conflicting_checksums
    mismatched_groups.flat_map { |g| g.map(&:checksum) }.uniq
  end

  # For the popover's "N/M match": among the distinct computers in
  # this instance's comparison group, how many reported the same
  # checksum (the instance's own computer included). nil when the
  # instance doesn't take part in any comparison.
  def match_counts(instance)
    key = self.class.key_for(instance)
    group = key && @groups[key]
    return nil unless group

    by_computer = group.group_by(&:computer_id)
    matching = by_computer.count { |_cid, insts| insts.any? { |i| i.checksum == instance.checksum } }
    { count: matching, total: by_computer.size }
  end

  private

  def mismatched_groups
    @groups.values.select { |g| g.map(&:checksum).uniq.size > 1 }
  end

  def disagreeing_ids
    @disagreeing_ids ||= mismatched_groups.each_with_object(Set.new) do |group, ids|
      votes = group.group_by(&:checksum)
                   .transform_values { |insts| insts.map(&:computer_id).uniq.size }
      top = votes.values.max
      leaders = votes.select { |_cs, n| n == top }.keys
      consensus = leaders.size == 1 ? leaders.first : nil
      group.each { |i| ids << i.id unless i.checksum == consensus }
    end
  end
end
