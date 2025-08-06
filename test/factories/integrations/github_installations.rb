FactoryBot.define do
  factory :integrations_github_installation, class: "Integrations::GithubInstallation" do
    team { nil }
    oauth_github_account { nil }
    name { "MyString" }
  end
end
