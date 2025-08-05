# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self, :https
    policy.font_src    :self, :https, :data
    policy.img_src     :self, :https, :data
    policy.object_src  :none
    
    # Allow trusted CDNs for JavaScript libraries
    policy.script_src  :self, :https, :unsafe_inline, :unsafe_eval,
                       "https://cdn.jsdelivr.net",
                       "https://unpkg.com",
                       "https://cdnjs.cloudflare.com",
                       "https://cdn.skypack.dev",
                       "https://esm.sh",
                       "https://ga.jspm.io"
    
    # Allow trusted CDNs for CSS libraries
    policy.style_src   :self, :https, :unsafe_inline,
                       "https://cdn.jsdelivr.net",
                       "https://unpkg.com",
                       "https://cdnjs.cloudflare.com",
                       "https://fonts.googleapis.com"
    
    # Allow Google Fonts
    policy.font_src    :self, :https, :data,
                       "https://fonts.gstatic.com"
    
    # Specify URI for violation reports
    # policy.report_uri "/csp-violation-report-endpoint"
  end

  # Generate session nonces for permitted importmap, inline scripts, and inline styles.
  config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
  config.content_security_policy_nonce_directives = %w(script-src style-src)

  # Report violations without enforcing the policy.
  # config.content_security_policy_report_only = true
end
