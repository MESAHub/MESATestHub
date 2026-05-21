FactoryBot.define do
  factory :test_case_commit do
    association :commit
    association :test_case
    status { -1 }
    submission_count { 0 }
    computer_count { 0 }
    checksum_count { 0 }
    passed_count { 0 }
    failed_count { 0 }

    trait :passing do
      status { 0 }
      passed_count { 1 }
      checksum_count { 1 }
    end

    trait :failing do
      status { 1 }
      failed_count { 1 }
    end

    trait :mixed_checksums do
      status { 2 }
      passed_count { 2 }
      checksum_count { 2 }
    end

    trait :mixed do
      status { 3 }
      passed_count { 1 }
      failed_count { 1 }
    end
  end
end
