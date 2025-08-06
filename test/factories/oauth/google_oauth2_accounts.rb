FactoryBot.define do
  factory :oauth_google_oauth2_account, class: "Oauth::GoogleOauth2Account" do
    uid { "MyString" }
    data { "" }
    team { nil }
    user { nil }
  end
end
