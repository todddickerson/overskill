FactoryBot.define do
  factory :webhooks_incoming_oauth_google_oauth2_account_webhook, class: "Webhooks::Incoming::Oauth::GoogleOauth2AccountWebhook" do
    data { "" }
    processed_at { "2025-08-06 15:59:48" }
    verified_at { "2025-08-06 15:59:48" }
    oauth_google_oauth2_account { nil }
  end
end
