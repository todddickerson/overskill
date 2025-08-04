class AppSetting < ApplicationRecord
  belongs_to :app
  
  # Predefined setting types for non-technical users
  SETTING_TYPES = {
    'general' => 'General Settings',
    'api' => 'API Configuration',
    'email' => 'Email Settings',
    'analytics' => 'Analytics & Tracking',
    'social' => 'Social Media',
    'payment' => 'Payment Processing'
  }.freeze
  
  # Common settings with user-friendly names and defaults
  COMMON_SETTINGS = {
    # General
    'app_name' => { type: 'general', label: 'App Name', placeholder: 'My Awesome App', required: true },
    'app_description' => { type: 'general', label: 'App Description', placeholder: 'Describe your app...', required: false },
    'support_email' => { type: 'general', label: 'Support Email', placeholder: 'support@example.com', required: false },
    
    # Email
    'email_from_name' => { type: 'email', label: 'From Name', placeholder: 'My App', required: false },
    'email_from_address' => { type: 'email', label: 'From Email', placeholder: 'noreply@example.com', required: false },
    
    # Analytics
    'google_analytics_id' => { type: 'analytics', label: 'Google Analytics ID', placeholder: 'G-XXXXXXXXXX', required: false },
    'mixpanel_token' => { type: 'analytics', label: 'Mixpanel Token', placeholder: 'Your Mixpanel token', required: false },
    
    # Social
    'facebook_app_id' => { type: 'social', label: 'Facebook App ID', placeholder: 'Your Facebook App ID', required: false },
    'twitter_handle' => { type: 'social', label: 'Twitter/X Handle', placeholder: '@yourapp', required: false }
  }.freeze
  
  # Sensitive keys that should be encrypted
  ENCRYPTED_KEYS = %w[
    api_key
    secret_key
    password
    token
    private_key
    client_secret
  ].freeze
  
  validates :key, presence: true, uniqueness: { scope: :app_id }
  validates :setting_type, inclusion: { in: SETTING_TYPES.keys }
  
  before_save :auto_encrypt_sensitive_values
  
  scope :by_type, ->(type) { where(setting_type: type) }
  scope :required, -> { where(key: COMMON_SETTINGS.select { |k, v| v[:required] }.keys) }
  
  def display_name
    COMMON_SETTINGS.dig(key, :label) || key.humanize
  end
  
  def placeholder
    COMMON_SETTINGS.dig(key, :placeholder) || ''
  end
  
  def required?
    COMMON_SETTINGS.dig(key, :required) || false
  end
  
  def common_setting?
    COMMON_SETTINGS.key?(key)
  end
  
  private
  
  def auto_encrypt_sensitive_values
    # Auto-encrypt if key contains sensitive words
    if ENCRYPTED_KEYS.any? { |word| key.to_s.downcase.include?(word) }
      self.encrypted = true
    end
  end
end
