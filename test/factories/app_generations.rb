FactoryBot.define do
  factory :app_generation do
    association :team
    association :app
    prompt { "MyText" }
    enhanced_prompt { "MyText" }
    status { "MyString" }
    ai_model { "MyString" }
    started_at { "2025-07-29 14:04:41" }
    completed_at { "2025-07-29 14:04:41" }
    duration_seconds { 1 }
    input_tokens { 1 }
    output_tokens { 1 }
    total_cost { 1 }
    error_message { "MyText" }
    retry_count { 1 }
  end
end
