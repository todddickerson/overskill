class BuildLog < ApplicationRecord
  belongs_to :deployment_log

  LEVELS = %w[debug info warning error success].freeze

  validates :level, inclusion: {in: LEVELS}
  validates :message, presence: true

  scope :errors, -> { where(level: "error") }
  scope :warnings, -> { where(level: "warning") }

  def color_class
    case level
    when "error"
      "text-red-600 dark:text-red-400"
    when "warning"
      "text-yellow-600 dark:text-yellow-400"
    when "success"
      "text-green-600 dark:text-green-400"
    when "info"
      "text-blue-600 dark:text-blue-400"
    else
      "text-gray-600 dark:text-gray-400"
    end
  end
end
