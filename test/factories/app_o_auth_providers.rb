FactoryBot.define do
  factory :app_o_auth_provider do
    app { nil }
    provider { "MyString" }
    client_id { "MyString" }
    client_secret { "MyString" }
    domain { "MyString" }
    redirect_uri { "MyString" }
    scopes { "MyText" }
    enabled { false }
  end
end
