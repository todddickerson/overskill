FactoryBot.define do
  factory :webhooks_incoming_oauth_github_account_webhook, class: "Webhooks::Incoming::Oauth::GithubAccountWebhook" do
    data { "" }
    processed_at { "2025-08-06 16:00:23" }
    verified_at { "2025-08-06 16:00:23" }
    oauth_github_account { nil }
  end
end
