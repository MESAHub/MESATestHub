namespace :db do
  desc "Change null diff to 2 (undetermined)."
  task fix_diffs: :environment do
    TestInstance.where(diff: nil).each do |ti|
      ti.diff = 2
      ti.save!
    end
  end
end
