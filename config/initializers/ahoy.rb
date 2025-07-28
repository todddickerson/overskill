class Ahoy::Store < Ahoy::DatabaseStore
end

# set to true for JavaScript tracking
Ahoy.api = false

# set to true for geocoding (requires Geocoder gem)
# Ahoy.geocode = false

# period for cookies
Ahoy.visit_duration = 30.minutes

# period for attributing visits to users
Ahoy.user_duration = 30.days

# server timezone
Ahoy.time_zone = "UTC"