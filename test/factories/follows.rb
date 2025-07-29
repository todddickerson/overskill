FactoryBot.define do
  factory :follow do
    association :team
    follower_id { nil }
    followed_id { nil }
  end
end
