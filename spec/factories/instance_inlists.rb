FactoryBot.define do
  factory :instance_inlist do
    inlist_name { "MyString" }
    runtime_minutes { 1.5 }
    retries { 1 }
    steps { 1 }
    newton_retries { "MyString" }
    integer { "MyString" }
    newton_iters { 1 }
    test_instance { nil }
  end
end
