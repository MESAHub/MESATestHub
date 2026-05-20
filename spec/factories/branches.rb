FactoryBot.define do
  factory :branch do
    sequence(:name) { |n| "branch-#{n}" }
    merged { false }
  end
end
