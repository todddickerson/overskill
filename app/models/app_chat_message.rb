class AppChatMessage < ApplicationRecord
  belongs_to :app
  belongs_to :user, optional: true
  belongs_to :app_version, optional: true

  validates :role, inclusion: {in: %w[user assistant system]}

  # AI response statuses for better user feedback
  STATUSES = %w[planning executing generating completed failed validation_error].freeze
  validates :status, inclusion: {in: STATUSES}, allow_nil: true

  # Ensure only assistant messages can have status
  validate :status_only_for_assistant

  # Broadcast to chat channel when messages are created or updated
  after_create_commit :broadcast_message_created
  after_update_commit :broadcast_message_updated, if: :should_broadcast_update?

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

  def generating?
    status == "generating"
  end

  def has_generation_data?
    # Check if this message has progress data or is actively being processed
    generating? || executing? || planning? || status.present?
  end

  def app_generated?
    # Check if this message resulted in a completed app
    completed? && app.present? && app.status == "ready"
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

  def partial_name
    # Use V5 partial if this is an agent message with V5 fields
    use_v5_partial? ? "agent_reply_v5" : "chat_message"
  end

  private

  def status_only_for_assistant
    if status.present? && role != "assistant"
      errors.add(:status, "can only be set for assistant messages")
    end
  end

  def broadcast_message_created
    broadcast_append_to(
      "app_#{app.id}_chat",
      target: "chat_messages",
      partial: "account/app_editors/chat_message",
      locals: {message: self}
    )

    # Also trigger scroll to bottom
    broadcast_append_to(
      "app_#{app.id}_chat",
      target: "chat_messages",
      html: "<div data-controller='chat-scroller' data-chat-scroller-target='trigger'></div>"
    )
  end

  def broadcast_message_updated
    Rails.logger.info "[AppChatMessage] Broadcasting update for message #{id}, partial: #{partial_name}, metadata: #{metadata.inspect}"

    broadcast_replace_to(
      "app_#{app.id}_chat",
      target: "app_chat_message_#{id}",
      partial: "account/app_editors/#{partial_name}",
      locals: {message: self}
    )

    # Trigger scroll to bottom on updates too (for streaming messages)
    broadcast_append_to(
      "app_#{app.id}_chat",
      target: "chat_messages",
      html: "<div data-controller='chat-scroller' data-chat-scroller-target='trigger'></div>"
    )
  end

  def should_broadcast_update?
    # Broadcast on any relevant field change for V5
    saved_change_to_content? ||
      saved_change_to_status? ||
      saved_change_to_thinking_status? ||
      saved_change_to_loop_messages? ||
      saved_change_to_tool_calls? ||
      saved_change_to_iteration_count? ||
      saved_change_to_is_code_generation? ||
      saved_change_to_conversation_flow? ||
      saved_change_to_metadata?  # IMPORTANT: Broadcast when build metadata updates
  end

  def use_v5_partial?
    # Use V5 partial if any V5 fields are populated
    role == "assistant" && (
      thinking_status.present? ||
      loop_messages.present? ||
      tool_calls.present? ||
      iteration_count.to_i > 0 ||
      is_code_generation? ||
      conversation_flow.present? ||
      metadata.present? && metadata["workflow_run_id"].present?  # Use V5 for build status
    )
  end
end
