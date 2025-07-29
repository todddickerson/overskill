FactoryBot.define do
  factory :app_collaborator do
    association :team
    app { nil }
    membership { nil }
    role { "MyString" }
    github_username { "MyString" }
    permissions_synced { false }
  end
end
