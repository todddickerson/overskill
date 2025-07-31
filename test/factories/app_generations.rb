FactoryBot.define do
  factory :app_generation do
    association :team
    association :app
    prompt { "Create a simple todo list app" }
    enhanced_prompt { nil }
    status { "pending" }
    ai_model { "moonshotai/kimi-k2" }
    started_at { Time.current }
    completed_at { nil }
    duration_seconds { nil }
    input_tokens { nil }
    output_tokens { nil }
    total_cost { nil }
    error_message { nil }
    retry_count { 0 }

    trait :processing do
      status { "processing" }
      enhanced_prompt { "Create a simple todo list app with modern UI" }
    end

    trait :completed do
      status { "completed" }
      enhanced_prompt { "Create a simple todo list app with modern UI" }
      completed_at { Time.current }
      duration_seconds { 45 }
      input_tokens { 500 }
      output_tokens { 2000 }
      total_cost { 0.025 }
    end

    trait :failed do
      status { "failed" }
      error_message { "API rate limit exceeded" }
      completed_at { Time.current }
      duration_seconds { 5 }
      retry_count { 3 }
    end
  end
end
