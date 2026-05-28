FactoryBot.define do
  factory :claim do
    association :computer
    association :commit
    scope { 'build' }
    status { 'pending' }
    expires_at { 15.minutes.from_now }

    trait :test_scope do
      scope { 'test' }
      # TCC gets created on the same commit as the claim so the
      # tcc_commit_matches_claim_commit validation passes.
      after(:build) do |claim, _ev|
        claim.test_case_commit ||= create(:test_case_commit,
                                          commit: claim.commit)
      end
    end

    trait :fulfilled do
      status { 'fulfilled' }
      fulfilled_at { Time.current }
    end

    trait :expired do
      status { 'expired' }
      expires_at { 5.minutes.ago }
    end
  end
end
