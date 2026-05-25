FactoryBot.define do
  factory :submission do
    association :commit
    association :computer
    compiled { true }
    entire { true }
    empty { false }
    compiler { "gfortran" }
    compiler_version { "12.2" }
    sdk_version { "26.3.2" }
    math_backend { "OpenBLAS" }
    platform_version { "linux x86_64" }
  end
end
