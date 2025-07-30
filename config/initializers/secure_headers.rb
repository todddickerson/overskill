SecureHeaders::Configuration.default do |config|
  config.x_frame_options = "SAMEORIGIN"
  config.x_content_type_options = "nosniff"
  config.x_xss_protection = "1; mode=block"
  config.x_permitted_cross_domain_policies = "none"
  config.referrer_policy = %w[origin-when-cross-origin strict-origin-when-cross-origin]
  
  # Disable CSP for now - can be configured later
  config.csp = SecureHeaders::OPT_OUT
  
  # Basic cookie security
  if Rails.env.production?
    config.cookies = {
      secure: true,
      httponly: true,
      samesite: {
        lax: true
      }
    }
  else
    # In development, disable SecureHeaders cookie modification
    config.cookies = SecureHeaders::OPT_OUT
  end
end