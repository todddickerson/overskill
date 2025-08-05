FactoryBot.define do
  factory :app_audit_log do
    association :app
    action_type { "MyString" }
    performed_by { "MyString" }
    target_resource { "MyString" }
    resource_id { nil }
    change_details { "MyText" }
    ip_address { "MyString" }
    user_agent { "MyString" }
    occurred_at { "2025-08-05 16:13:04" }
  end
end
