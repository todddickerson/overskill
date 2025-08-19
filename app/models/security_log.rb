# frozen_string_literal: true

class SecurityLog < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :app, optional: true
  
  # Event types for security monitoring
  EVENT_TYPES = %w[
    prompt_injection_attempt
    rate_limit_exceeded
    suspicious_output
    api_key_exposure
    system_prompt_leak
    excessive_usage
    malicious_code_attempt
    unauthorized_access
  ].freeze
  
  validates :event_type, presence: true, inclusion: { in: EVENT_TYPES }
  validates :details, presence: true
  
  # Scopes for querying
  scope :recent, -> { order(created_at: :desc) }
  scope :by_user, ->(user) { where(user: user) }
  scope :by_app, ->(app) { where(app: app) }
  scope :by_type, ->(type) { where(event_type: type) }
  scope :high_risk, -> { where("(details->>'risk_score')::int >= ?", 50) }
  
  # Check if user has recent security issues
  def self.user_has_recent_violations?(user, hours: 24)
    where(user: user)
      .where(created_at: hours.hours.ago..Time.current)
      .exists?
  end
  
  # Get violation count for user
  def self.user_violation_count(user, hours: 24)
    where(user: user)
      .where(created_at: hours.hours.ago..Time.current)
      .count
  end
end