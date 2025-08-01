FactoryBot.define do
  factory :app_version_file do
    app_version { nil }
    app_file { nil }
    content { "MyText" }
    action { "MyString" }
  end
end
