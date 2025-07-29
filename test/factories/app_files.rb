FactoryBot.define do
  factory :app_file do
    association :team
    app { nil }
    path { "MyString" }
    content { "MyText" }
    file_type { "MyString" }
    size_bytes { 1 }
    checksum { "MyString" }
    is_entry_point { false }
  end
end
