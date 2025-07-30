FactoryBot.define do
  factory :app_chat_message do
    association :app
    content { "Please add a button to the page" }
    role { "user" }
    response { nil }
    status { "pending" }

    trait :user_message do
      role { "user" }
      status { "pending" }
      response { nil }
    end

    trait :assistant_message do
      role { "assistant" }
      content { "I've added a button to your page. The button is styled with Tailwind CSS and includes hover effects." }
      status { "completed" }
      response { nil }
    end

    trait :processing do
      status { "processing" }
    end

    trait :completed do
      status { "completed" }
      response { "Changes applied successfully" }
    end

    trait :failed do
      status { "failed" }
      response { "Error: Unable to process request" }
    end
  end
end
