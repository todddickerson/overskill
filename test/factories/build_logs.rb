FactoryBot.define do
  factory :build_log do
    deployment_log { nil }
    level { "MyString" }
    message { "MyText" }
    created_at { "2025-08-04 12:43:38" }
  end
end
