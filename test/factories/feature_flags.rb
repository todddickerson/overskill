FactoryBot.define do
  factory :feature_flag do
    name { "MyString" }
    enabled { false }
    percentage { 1 }
    description { "MyText" }
  end
end
