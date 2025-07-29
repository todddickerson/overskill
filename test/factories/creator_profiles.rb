FactoryBot.define do
  factory :creator_profile do
    association :team
    username { "MyString" }
    bio { "MyText" }
    level { 1 }
    total_earnings { 1 }
    total_sales { 1 }
    verification_status { "MyString" }
    featured_until { "2025-07-29 13:47:58" }
    slug { "MyString" }
    stripe_account_id { nil }
    public_email { "MyString" }
    website_url { "MyString" }
    twitter_handle { "MyString" }
    github_username { "MyString" }
  end
end
