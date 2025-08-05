FactoryBot.define do
  factory :app_security_policy do
    association :app
    policy_name { "MyString" }
    policy_type { "MyString" }
    enabled { false }
    configuration { "MyText" }
    description { "MyText" }
    last_violation { "2025-08-05 16:08:10" }
    violation_count { 1 }
  end
end
