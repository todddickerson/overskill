FactoryBot.define do
  factory :app_domain do
    app { nil }
    domain { "MyString" }
    status { "MyString" }
    verified_at { "2025-08-04 12:51:15" }
    ssl_status { "MyString" }
    cloudflare_zone_id { "MyString" }
    cloudflare_record_id { "MyString" }
  end
end
