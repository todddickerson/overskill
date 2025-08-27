if heroku?
  $redis = Redis.new(url: ENV["REDIS_URL"], ssl_params: {verify_mode: OpenSSL::SSL::VERIFY_NONE}) # standard:disable Style/GlobalVars
else
  # Set up global Redis connection for development/test to ensure consistency
  # This fixes streaming tool coordinator Redis tracking
  $redis = Redis.new(url: ENV["REDIS_URL"] || "redis://localhost:6379/0") # standard:disable Style/GlobalVars
end
