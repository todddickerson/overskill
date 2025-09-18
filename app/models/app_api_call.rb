class AppApiCall < ApplicationRecord
  belongs_to :app

  validates :http_method, presence: true
  validates :path, presence: true
  validates :status_code, presence: true, numericality: {in: 100..599}
  validates :occurred_at, presence: true

  scope :recent, -> { order(occurred_at: :desc) }
  scope :by_method, ->(method) { where(http_method: method.to_s.upcase) }
  scope :successful, -> { where(status_code: 200..299) }
  scope :errors, -> { where(status_code: 400..599) }
  scope :today, -> { where(occurred_at: Date.current.beginning_of_day..Date.current.end_of_day) }
  scope :last_24_hours, -> { where(occurred_at: 24.hours.ago..Time.current) }

  def successful?
    status_code >= 200 && status_code < 300
  end

  def client_error?
    status_code >= 400 && status_code < 500
  end

  def server_error?
    status_code >= 500
  end

  def time_ago
    return "just now" if occurred_at > 1.minute.ago
    return "#{((Time.current - occurred_at) / 1.minute).round}m ago" if occurred_at > 1.hour.ago
    return "#{((Time.current - occurred_at) / 1.hour).round}h ago" if occurred_at > 1.day.ago
    "#{((Time.current - occurred_at) / 1.day).round}d ago"
  end

  def status_color
    case status_code
    when 200..299 then "text-green-600 dark:text-green-400"
    when 300..399 then "text-blue-600 dark:text-blue-400"
    when 400..499 then "text-yellow-600 dark:text-yellow-400"
    when 500..599 then "text-red-600 dark:text-red-400"
    else "text-gray-600 dark:text-gray-400"
    end
  end

  def status_icon
    case status_code
    when 200..299 then "fas fa-check-circle"
    when 300..399 then "fas fa-arrow-right"
    when 400..499 then "fas fa-exclamation-triangle"
    when 500..599 then "fas fa-times-circle"
    else "fas fa-question-circle"
    end
  end
end
