FactoryBot.define do
  factory :app do
    association :team
    name { "MyString" }
    slug { "MyString" }
    description { "MyText" }
    creator { nil }
    prompt { "MyText" }
    app_type { "MyString" }
    framework { "MyString" }
    status { "MyString" }
    visibility { "MyString" }
    base_price { 1 }
    stripe_product_id { nil }
    preview_url { "MyString" }
    production_url { "MyString" }
    github_repo { "MyString" }
    total_users { 1 }
    total_revenue { 1 }
    rating { 1 }
    featured { false }
    featured_until { "2025-07-29 14:02:54" }
    launch_date { "2025-07-29 14:02:54" }
    ai_model { "MyString" }
    ai_cost { 1 }
  end
end
