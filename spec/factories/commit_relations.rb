FactoryBot.define do
  factory :commit_relation do
    parent { build(:commit) }
    child  { build(:commit) }
    parent_index { 0 }
  end
end
