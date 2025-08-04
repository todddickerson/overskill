FactoryBot.define do
  factory :deployment_log do
    app { nil }
    environment { "MyString" }
    status { "MyString" }
    initiated_by { nil }
    deployment_url { "MyString" }
    error_message { "MyText" }
    started_at { "2025-08-04 12:43:30" }
    completed_at { "2025-08-04 12:43:30" }
    rollback_from { nil }
    deployed_version { "MyString" }
    build_output { "MyText" }
  end
end
