FactoryBot.define do
  factory :computer do
    sequence(:name) { |n| "computer-#{n}" }
    platform { "linux" }
    processor { "Intel Xeon" }
    ram_gb { 16 }
    association :user
  end
end
