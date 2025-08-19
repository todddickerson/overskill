# frozen_string_literal: true

class AlertService
  SEVERITY_LEVELS = [:low, :medium, :high, :critical].freeze
  
  class << self
    def security_alert(message, severity: :medium, details: {})
      Rails.logger.error "[SECURITY ALERT - #{severity.upcase}] #{message}"
      
      # Log details if provided
      if details.any?
        Rails.logger.error "[SECURITY ALERT DETAILS] #{details.to_json}"
      end
      
      # Send to monitoring service if configured
      if ENV['SLACK_WEBHOOK_URL'].present? && severity.in?([:high, :critical])
        send_slack_alert(message, severity, details)
      end
      
      # Send email for critical alerts
      if severity == :critical && ENV['ADMIN_EMAIL'].present?
        SecurityMailer.critical_alert(message, details).deliver_later
      end
      
      # Track in database for audit trail
      track_alert(message, severity, details)
    end
    
    def usage_alert(user, app, metric, value, threshold)
      message = "User #{user.id} exceeded #{metric} threshold: #{value} > #{threshold}"
      
      Rails.logger.warn "[USAGE ALERT] #{message}"
      
      # Notify user if needed
      if value > threshold * 1.5
        # Consider blocking or rate limiting
        security_alert(
          "Excessive usage detected for user #{user.id}",
          severity: :high,
          details: {
            user_id: user.id,
            app_id: app&.id,
            metric: metric,
            value: value,
            threshold: threshold
          }
        )
      end
    end
    
    private
    
    def send_slack_alert(message, severity, details)
      # Send to Slack webhook
      webhook_url = ENV['SLACK_WEBHOOK_URL']
      
      payload = {
        text: ":warning: Security Alert (#{severity.upcase})",
        attachments: [
          {
            color: severity_color(severity),
            title: message,
            fields: details.map { |k, v| { title: k.to_s.humanize, value: v.to_s, short: true } },
            footer: "Overskill Security",
            ts: Time.current.to_i
          }
        ]
      }
      
      HTTParty.post(webhook_url, 
        body: payload.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
    rescue => e
      Rails.logger.error "[ALERT SERVICE] Failed to send Slack alert: #{e.message}"
    end
    
    def severity_color(severity)
      case severity
      when :critical then 'danger'
      when :high then 'warning'
      when :medium then 'warning'
      else 'good'
      end
    end
    
    def track_alert(message, severity, details)
      # Store in cache for rate limiting
      cache_key = "alerts:#{severity}:#{Time.current.strftime('%Y%m%d%H')}"
      Rails.cache.increment(cache_key, 1, expires_in: 1.hour)
      
      # Could also store in database if needed
      # AlertLog.create!(message: message, severity: severity, details: details)
    end
  end
end