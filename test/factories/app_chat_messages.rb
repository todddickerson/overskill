FactoryBot.define do
  factory :app_chat_message do
    app { nil }
    content { "MyText" }
    role { "MyString" }
    response { "MyText" }
    status { "MyString" }
  end
end
