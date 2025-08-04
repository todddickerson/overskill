FactoryBot.define do
  factory :app_table_column do
    app_table { nil }
    name { "MyString" }
    column_type { "MyString" }
    options { "MyText" }
    required { false }
    default_value { "MyString" }
  end
end
