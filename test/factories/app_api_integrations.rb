FactoryBot.define do
  factory :app_api_integration do
    app { nil }
    name { "MyString" }
    base_url { "MyString" }
    auth_type { "MyString" }
    api_key { "MyString" }
    path_prefix { "MyString" }
    additional_headers { "MyText" }
    enabled { false }
  end
end
