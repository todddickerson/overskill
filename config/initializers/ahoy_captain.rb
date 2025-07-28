AhoyCaptain.configure do |config|
  # Configure cache (using Rails cache)
  config.cache_store = Rails.cache
  
  # Configure models
  config.event_class = "Ahoy::Event"
  config.visit_class = "Ahoy::Visit"
end