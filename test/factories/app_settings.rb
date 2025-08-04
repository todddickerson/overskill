FactoryBot.define do
  factory :app_setting do
    association :app
    key { "APP_NAME" }
    value { "My Test App" }
    encrypted { false }
    description { "The name of the application" }
    setting_type { "general" }
  end
end
