class AppOauthProvider < ApplicationRecord
  # OAuth provider configuration for generated apps
  # Stores OAuth credentials and endpoints for third-party integrations
  
  belongs_to :app
  belongs_to :team
  
  # OAuth provider types
  PROVIDER_TYPES = %w[google github facebook twitter discord slack spotify].freeze
  
  # Encryption for sensitive credentials
  encrypts :client_secret
  encrypts :refresh_token
  
  # Validations
  validates :provider_type, presence: true, inclusion: { in: PROVIDER_TYPES }
  validates :client_id, presence: true
  validates :client_secret, presence: true
  validates :app, presence: true
  validates :team, presence: true
  
  # Scopes
  scope :active, -> { where(enabled: true) }
  scope :by_provider, ->(type) { where(provider_type: type) }
  
  # Check if provider is configured
  def configured?
    client_id.present? && client_secret.present?
  end
  
  # Get authorization URL for OAuth flow
  def authorization_url(redirect_uri)
    case provider_type
    when 'google'
      "https://accounts.google.com/o/oauth2/v2/auth?" \
      "client_id=#{client_id}&" \
      "redirect_uri=#{redirect_uri}&" \
      "response_type=code&" \
      "scope=#{scope}&" \
      "access_type=offline"
    when 'github'
      "https://github.com/login/oauth/authorize?" \
      "client_id=#{client_id}&" \
      "redirect_uri=#{redirect_uri}&" \
      "scope=#{scope}"
    else
      authorization_endpoint
    end
  end
  
  # Default scopes for each provider
  def default_scope
    case provider_type
    when 'google' then 'openid email profile'
    when 'github' then 'read:user user:email'
    when 'discord' then 'identify email'
    when 'slack' then 'identity.basic identity.email'
    else ''
    end
  end
  
  # Set default values
  before_validation :set_defaults
  
  private
  
  def set_defaults
    self.scope ||= default_scope
    self.enabled = true if enabled.nil?
  end
end