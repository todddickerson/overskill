# frozen_string_literal: true

module Ai
  module Tools
    class WebContentTool
      attr_reader :app, :logger
      
      def initialize(app)
        @app = app
        @logger = Rails.logger
        @extraction_service = WebContentExtractionService.new
      end
      
      # Tool: os-fetch-webpage
      # Fetches and extracts clean content from a webpage for LLM analysis
      def execute(params)
        url = params['url'] || params[:url]
        extract_images = params['extract_images'] || params[:extract_images] || false
        use_cache = params['use_cache'] || params[:use_cache] || true
        
        # Validate URL is provided
        return error_response("URL parameter is required") if url.blank?
        
        @logger.info "[WebContentTool] Fetching content from: #{url}"
        
        # Extract content using the service
        result = @extraction_service.extract_for_llm(
          url,
          use_cache: use_cache
        )
        
        # Check for errors
        if result[:error]
          @logger.error "[WebContentTool] Failed to fetch #{url}: #{result[:error]}"
          return error_response(result[:error])
        end
        
        # Format response for the agent
        response = format_response(result)
        
        # Log success
        @logger.info "[WebContentTool] Successfully extracted #{result[:word_count]} words from #{url}"
        
        success_response(response)
      rescue StandardError => e
        @logger.error "[WebContentTool] Unexpected error: #{e.message}"
        @logger.error e.backtrace.first(5).join("\n")
        error_response("Failed to fetch webpage: #{e.message}")
      end
      
      private
      
      def format_response(result)
        response = []
        
        # Add metadata header
        response << "=== Webpage Content Extracted ==="
        response << "URL: #{result[:url]}"
        response << "Title: #{result[:title]}"
        response << "Word Count: #{result[:word_count]}"
        response << "Character Count: #{result[:char_count]}"
        response << "Extracted At: #{result[:extracted_at]}"
        
        if result[:truncated]
          response << "⚠️ Content was truncated due to length"
        end
        
        response << "\n=== Content ==="
        response << result[:content]
        
        response.join("\n")
      end
      
      def success_response(content)
        {
          success: true,
          content: content
        }
      end
      
      def error_response(message)
        {
          success: false,
          error: message,
          content: "Failed to fetch webpage: #{message}"
        }
      end
    end
  end
end