FactoryBot.define do
  factory :integrations_google_oauth2_installation, class: "Integrations::GoogleOauth2Installation" do
    team { nil }
    oauth_google_oauth2_account { nil }
    name { "MyString" }
  end
end
