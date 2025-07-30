class AppChatMessage < ApplicationRecord
  belongs_to :app

  validates :content, presence: true
  validates :role, inclusion: {in: %w[user assistant system]}

  scope :conversation, -> { where(role: %w[user assistant]) }

  def processing?
    status == "processing"
  end

  def completed?
    status == "completed"
  end

  def failed?
    status == "failed"
  end
end
