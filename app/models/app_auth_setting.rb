class AppAuthSetting < ApplicationRecord
  belongs_to :app
  
  # Visibility options matching the UI mockup
  enum :visibility, {
    private_login_required: 0,      # Only invited/whitelisted users can access
    public_login_required: 1,       # Anyone can sign up but must login to access
    public_no_login: 2              # Completely public, no authentication required
  }, prefix: true
  
  # Serialize JSON arrays for providers and domains (Rails 8 syntax)
  serialize :allowed_providers, coder: JSON, type: Array
  serialize :allowed_email_domains, coder: JSON, type: Array
  
  # Validations
  validates :visibility, presence: true
  validates :allowed_providers, presence: true
  
  # Callbacks
  after_initialize :set_defaults, if: :new_record?
  before_save :clean_email_domains
  
  # Helper methods
  def allows_provider?(provider)
    allowed_providers.include?(provider.to_s)
  end
  
  def allows_email_domain?(email)
    return true if allowed_email_domains.blank? || allowed_email_domains.empty?
    
    domain = email.to_s.split('@').last
    allowed_email_domains.include?(domain)
  end
  
  def requires_authentication?
    !visibility_public_no_login?
  end
  
  def allows_public_signup?
    visibility_public_login_required? && allow_signups
  end
  
  # Export settings for frontend
  def to_frontend_config
    {
      visibility: visibility,
      requires_auth: requires_authentication?,
      allow_signups: allow_signups,
      allow_anonymous: allow_anonymous,
      require_email_verification: require_email_verification,
      allowed_providers: allowed_providers,
      allowed_email_domains: allowed_email_domains,
      allows_public_signup: allows_public_signup?
    }
  end
  
  private
  
  def set_defaults
    self.visibility ||= 'public_login_required'
    self.allowed_providers ||= ['email', 'google', 'github']
    self.allowed_email_domains ||= []
    self.allow_signups = true if allow_signups.nil?
    self.require_email_verification = false if require_email_verification.nil?
    self.allow_anonymous = false if allow_anonymous.nil?
  end
  
  def clean_email_domains
    # Clean up domains - remove empty strings, lowercase, strip whitespace
    if allowed_email_domains.present?
      self.allowed_email_domains = allowed_email_domains
        .map(&:to_s)
        .map(&:strip)
        .map(&:downcase)
        .reject(&:blank?)
        .uniq
    end
  end
end
