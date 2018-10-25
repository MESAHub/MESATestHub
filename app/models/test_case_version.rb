class TestCaseVersion < ApplicationRecord
  belongs_to :version
  belongs_to :test_case
  has_many :test_instances
  has_many :computers, through: :test_instances

  # STATUS CODES:
  # -1: Untested: no submissions at all
  # 0:  Passing:  at least one submission, all passing
  # 1:  Failing:  at least one submission, all failing
  # 2:  Mixed Checksums: at least two submissions, all passing, different 
  #                      checksums
  # 3:  Mixed:    at least two submissions, some passing, some failing

  @@status_decoder = {
    -1 => :untested,
    0 => :passing,
    1 => :failing,
    2 => :mixed_checksums,
    3 => :mixed
  }

  @@status_encoder = @@status_decoder.invert

  def update_and_save_scalars
    update_submission_count
    update_computer_count
    update_status
    update_last_tested
    save
  end

  def update_submission_count
    self.submission_count = test_instances.count
  end

  def update_computer_count
    if submission_count == 0
      self.computer_count = 0
    else
      self.computer_count = computers.uniq.count
    end
  end

  def update_last_tested
    self.last_tested = test_instances.pluck(:created_at).max
  end

  def update_status
    # default status: untested
    self.status ||= @@status_encoder[:untested]
    return unless submission_count.positive?

    outcomes = test_instances.pluck(:passed).uniq
    if outcomes.count == 1
      # all results are the same, either passing or failing
      self.status = if outcomes.first
                      # if only outcome was true, all are passing
                      @@status_encoder[:passing]
                    else
                      # only outcomes was false; all are failing
                      @@status_encoder[:failing]
                    end
    elsif outcomes.count > 1
      # multiple outcomes (true and false present), so it's mixed
      self.status = @@status_encoder[:mixed]
    end
    # if all are passing, insure that checksums match
    if self.status == @@status_encoder[:passing]
      # collect unique non-nil checksums
      checksums = test_instances.pluck(:checksum).uniq.reject(&:nil?)
      # set to mixed checksums status if more than one distinct checksum
      # found
      self.status = @@status_encoder[:mixed_checksums] if checksums.count > 1
    end
  end
end
