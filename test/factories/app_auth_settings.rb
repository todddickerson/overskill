FactoryBot.define do
  factory :app_auth_setting do
    app { nil }
    visibility { 1 }
    allowed_providers { "MyText" }
    allowed_email_domains { "MyText" }
    require_email_verification { false }
    allow_signups { false }
    allow_anonymous { false }
  end
end
