module Ai
  module Services
    # MessageRouter - Determines how to handle incoming chat messages
    # Single responsibility: Route messages to appropriate handlers
    class MessageRouter
      attr_reader :message, :app
      
      def initialize(message)
        @message = message
        @app = message.app
      end
      
      # Determine the appropriate action for this message
      def route
        type = message_type
        confidence = calculate_confidence(type)
        
        {
          action: type == :generation ? :generate : type,
          confidence: confidence,
          reasoning: route_reasoning(type)
        }
      end
      
      private
      
      def calculate_confidence(type)
        case type
        when :generation
          app.app_files.empty? ? 1.0 : 0.8
        when :command
          message.content.start_with?('/') ? 1.0 : 0.7
        when :question
          message.content.end_with?('?') ? 0.9 : 0.6
        else
          0.7 # Default confidence for updates
        end
      end
      
      def route_reasoning(type)
        case type
        when :generation
          "App has no files, generating from scratch"
        when :update
          "Updating existing app files"
        when :question
          "Answering a question about the app"
        when :command
          "Executing a specific command"
        else
          "Defaulting to update action"
        end
      end
      
      public
      
      # Analyze message to determine type
      def message_type
        content = message.content.downcase
        
        # Check if this is the first message for a new app
        if app.app_files.empty? || !app.app_files.exists?(file_type: 'html')
          return :generation
        end
        
        # Check for specific command patterns
        if content.match?(/^\/(\w+)/) # Slash commands
          return :command
        end
        
        # Check for question indicators
        if content.match?(/\?$|^(what|why|how|when|where|who|can you|could you|explain)/)
          return :question
        end
        
        # Default to update for everything else
        :update
      end
      
      # Extract any special instructions or metadata
      def extract_metadata
        metadata = {}
        
        # Check for urgency indicators
        if message.content.match?(/urgent|asap|quickly|fast/i)
          metadata[:priority] = 'high'
        end
        
        # Check for specific file references
        if matches = message.content.scan(/[\w\-]+\.(html|css|js|json)/i)
          metadata[:referenced_files] = matches.map(&:first)
        end
        
        # Check for deployment intent
        if message.content.match?(/deploy|publish|live|production/i)
          metadata[:wants_deployment] = true
        end
        
        metadata
      end
    end
  end
end