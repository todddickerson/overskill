FactoryBot.define do
  factory :app_api_call do
    association :app
    http_method { "GET" }
    path { "/api/v1/users" }
    status_code { 200 }
    response_time { 150 }
    request_body { nil }
    response_body { '{"data": []}' }
    user_agent { "OverSkill-App/1.0" }
    ip_address { "192.168.1.1" }
    occurred_at { Time.current }
  end
end
