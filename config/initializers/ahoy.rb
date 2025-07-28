class Ahoy::Store < Ahoy::DatabaseStore
  # Associate visits and events with teams for multi-tenant tracking
  def track_visit(data)
    data[:team_id] = controller.current_team&.id if controller.respond_to?(:current_team)
    super(data)
  end

  def track_event(data)
    data[:team_id] = controller.current_team&.id if controller.respond_to?(:current_team)
    super(data)
  end
end

# Configuration for SaaS application
Ahoy.api = true # Enable JavaScript tracking for better client-side events

# Geocoding for user location insights
# we recommend configuring local geocoding as well
# see https://github.com/ankane/ahoy#geocoding
Ahoy.geocode = false

# Visit duration - how long until a new visit is created
Ahoy.visit_duration = 30.minutes

# Method to get the current user
Ahoy.user_method = :current_user

# Track bots for analytics (can be noisy)
Ahoy.track_bots = false

# Mask IPs for privacy (GDPR compliance)
Ahoy.mask_ips = true

# Track visits immediately (not in background job)
Ahoy.server_side_visits = :when_needed