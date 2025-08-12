# Enhanced V4 App Builder with improved chat UX feedback - FIXED VERSION
module Ai
  class AppBuilderV5
    include Rails.application.routes.url_helpers
    
    attr_reader :chat_message, :app, :broadcaster
    
    def initialize(chat_message)
      @chat_message = chat_message
      @app = chat_message.app || create_app
      @broadcaster = ChatProgressBroadcasterV2.new(chat_message)
      @start_time = Time.current
      @generated_files = []
      @errors = []
    end

    def execute!
      Rails.logger.info "[AppBuilderV5] Starting V5 builder for app ##{app.id}"
    end
  end
end