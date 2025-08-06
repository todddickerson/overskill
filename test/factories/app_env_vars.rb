FactoryBot.define do
  factory :app_env_var do
    association :app
    key { "MyString" }
    value { "MyString" }
    description { "MyString" }
    is_secret { false }
    is_system { false }
  end
end
