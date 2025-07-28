AhoyCaptain.configure do |config|
  # Application name shown in the dashboard
  config.app_name = "Overskill Analytics"
  
  # Customize the date range options
  config.ranges = [
    :today,
    :yesterday,
    :last_7_days,
    :last_30_days,
    :last_month,
    :this_month,
    :this_year,
    :last_year,
    :all_time
  ]
  
  # Set default date range
  config.default_range = :last_30_days
  
  # Configure which events to track
  config.event_names = [
    # Page views
    "$view",
    
    # Custom events for SaaS tracking
    "app_created",
    "app_published",
    "app_purchased",
    "app_deployed",
    "ai_generation_started",
    "ai_generation_completed",
    "ai_generation_failed",
    "user_signup",
    "user_upgraded",
    "payment_processed",
    "subscription_created",
    "subscription_cancelled"
  ]
  
  # Configure filters for the dashboard
  config.filters = [
    :browser,
    :device_type,
    :os,
    :country,
    :region,
    :city,
    :referrer,
    :referring_domain,
    :utm_source,
    :utm_medium,
    :utm_campaign
  ]
  
  # Configure charts
  config.charts = true
  
  # Configure tables
  config.tables = true
  
  # Show goals/conversions
  config.goals = true
  
  # Configure cache (using Rails cache)
  config.cache = Rails.cache
  
  # Cache duration
  config.cache_duration = 5.minutes
end