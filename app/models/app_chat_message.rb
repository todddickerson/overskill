class AppChatMessage < ApplicationRecord
  belongs_to :app
  belongs_to :user, optional: true
  belongs_to :app_version, optional: true

  validates :content, presence: true
  validates :role, inclusion: {in: %w[user assistant system]}

  # AI response statuses for better user feedback
  STATUSES = %w[planning executing generating completed failed validation_error].freeze
  validates :status, inclusion: {in: STATUSES}, allow_nil: true
  
  # Ensure only assistant messages can have status
  validate :status_only_for_assistant

  # Broadcast to chat channel when messages are created or updated
  after_create_commit :broadcast_message_created
  after_update_commit :broadcast_message_updated, if: :saved_change_to_content_or_status?

  scope :conversation, -> { where(role: %w[user assistant]) }

  def planning?
    status == "planning"
  end

  def executing?
    status == "executing"
  end

  def processing?
    status == "processing" || executing?
  end

  def completed?
    status == "completed"
  end

  def failed?
    status == "failed"
  end

  def status_icon
    case status
    when "planning"
      "fas fa-brain text-blue-500"
    when "executing"
      "fas fa-cogs text-yellow-500 animate-spin"
    when "completed"
      "fas fa-check-circle text-green-500"
    when "failed"
      "fas fa-exclamation-triangle text-red-500"
    else
      "fas fa-comment text-gray-500"
    end
  end

  def status_text
    case status
    when "planning"
      "Planning changes..."
    when "executing"
      "Executing changes..."
    when "completed"
      "Completed"
    when "failed"
      "Failed"
    else
      ""
    end
  end
  
  private
  
  def status_only_for_assistant
    if status.present? && role != 'assistant'
      errors.add(:status, 'can only be set for assistant messages')
    end
  end
  
  def broadcast_message_created
    broadcast_append_to(
      "app_#{app.id}_chat",
      target: "chat_messages",
      partial: "account/app_editors/chat_message",
      locals: { message: self }
    )
    
    # Also trigger scroll to bottom
    broadcast_append_to(
      "app_#{app.id}_chat",
      target: "chat_messages",
      html: "<div data-controller='chat-scroller' data-chat-scroller-target='trigger'></div>"
    )
  end
  
  def broadcast_message_updated
    broadcast_replace_to(
      "app_#{app.id}_chat",
      target: "app_chat_message_#{id}",
      partial: "account/app_editors/chat_message",
      locals: { message: self }
    )
  end
  
  def saved_change_to_content_or_status?
    saved_change_to_content? || saved_change_to_status?
  end
end
