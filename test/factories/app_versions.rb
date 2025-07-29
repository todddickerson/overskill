FactoryBot.define do
  factory :app_version do
    association :team
    app { nil }
    user { nil }
    commit_sha { "MyString" }
    commit_message { "MyString" }
    version_number { "MyString" }
    changelog { "MyText" }
    files_snapshot { "MyText" }
    changed_files { "MyText" }
    external_commit { false }
    deployed { false }
    published_at { "2025-07-29 14:06:55" }
  end
end
