# Enhanced Chat Progress Broadcaster with Turbo Streams and Rails 8 patterns
module Ai
  class ChatProgressBroadcasterV5
    include ActionView::RecordIdentifier
    include ActionView::Helpers::TagHelper
    
    attr_reader :chat_message, :app, :channel
    
    def initialize(chat_message)
      @chat_message = chat_message
      @app = chat_message.app
      @user = chat_message.user
      @channel = "ChatChannel:#{chat_message.id}"
      @start_time = Time.current
      @current_assistant_message = nil
    end

    def broadcast!
      Rails.logger.info "[ChatProgressBroadcasterV5] Broadcasting for app ##{app.id}"
    end
  end
end