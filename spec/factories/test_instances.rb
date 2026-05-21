FactoryBot.define do
  factory :test_instance do
    association :commit
    association :computer
    association :test_case
    compiler { "gfortran" }
    compiler_version { "12.2" }
    sdk_version { "26.3.2" }
    math_backend { "OpenBLAS" }
    platform_version { "linux x86_64" }
    computer_specification { "linux x86_64 26.3.2 OpenBLAS gfortran 12.2" }
    passed { true }
    fpe_checks { false }
    run_optional { false }
    resolution_factor { 1.0 }
    checksum { "abc1234" }

    trait :failing do
      passed { false }
      failure_type { "run_checksum" }
    end

    trait :inlists_full do
      run_optional { true }
    end

    trait :fpe do
      fpe_checks { true }
    end
  end
end
