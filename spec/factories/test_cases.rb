FactoryBot.define do
  factory :test_case do
    sequence(:name) { |n| "test_case_#{n}" }
    # `module` is a Ruby reserved word, so we set the column via the
    # hash-style attribute assignment that FactoryBot allows.
    add_attribute(:module) { "star" }
  end
end
