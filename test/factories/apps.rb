FactoryBot.define do
  factory :app do
    association :team
    name { "Test App #{SecureRandom.hex(3)}" }
    sequence(:slug) { |n| "test-app-#{n}" }
    description { "A test application" }
    prompt { "Create a simple test app" }
    app_type { "utility" }
    framework { "react" }
    status { "draft" }
    visibility { "private" }
    
    after(:build) do |app|
      if app.creator.nil?
        # Find existing membership or create a new one
        existing_membership = app.team.memberships.first
        app.creator = existing_membership || create(:membership, team: app.team)
      end
    end
    base_price { 0.0 }
    stripe_product_id { nil }
    preview_url { nil }
    production_url { nil }
    github_repo { nil }
    total_users { 0 }
    total_revenue { 0.0 }
    rating { 0.0 }
    featured { false }
    featured_until { nil }
    launch_date { nil }
    ai_model { nil }
    ai_cost { 0.0 }

    trait :generating do
      status { "generating" }
      ai_model { "moonshotai/kimi-k2" }
    end

    trait :generated do
      status { "generated" }
      ai_model { "moonshotai/kimi-k2" }
      ai_cost { 0.01 }
    end

    trait :published do
      status { "published" }
      visibility { "public" }
      base_price { 9.99 }
      launch_date { 1.week.ago }
    end

    trait :featured do
      featured { true }
      featured_until { 1.month.from_now }
    end

    trait :with_files do
      after(:create) do |app|
        create(:app_file, app: app, team: app.team, path: "index.html")
        create(:app_file, app: app, team: app.team, path: "app.js", file_type: "javascript", content: "console.log('app');")
        create(:app_file, app: app, team: app.team, path: "styles.css", file_type: "css", content: "body { margin: 0; }")
      end
    end

    trait :with_versions do
      after(:create) do |app|
        create(:app_version, app: app, version_number: "1.0.0")
        create(:app_version, app: app, version_number: "1.0.1")
      end
    end

    trait :with_chat_messages do
      after(:create) do |app|
        create(:app_chat_message, app: app, role: "user")
        create(:app_chat_message, app: app, role: "assistant")
      end
    end
  end
end
