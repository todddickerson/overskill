FactoryBot.define do
  factory :oauth_github_account, class: "Oauth::GithubAccount" do
    uid { "MyString" }
    data { "" }
    team { nil }
    user { nil }
  end
end
