module Ai
  # AI App Naming Service - Generates contextual app names based on prompts
  # Uses GPT-5 for fast, creative naming that matches the app's purpose
  class AppNamerService
    include Rails.application.routes.url_helpers
    
    # Maximum attempts for naming
    MAX_RETRIES = 2
    
    # Model preferences for naming (lightweight and fast)
    NAMING_MODEL_PREFERENCE = 'gpt-5'
    
    attr_reader :app, :prompt, :client_info
    
    def initialize(app)
      @app = app
      @prompt = extract_app_prompt
      setup_ai_client
    end
    
    def generate_name!
      Rails.logger.info "[AppNamer] Generating name for app ##{@app.id} based on: '#{@prompt}'"
      
      retries = 0
      
      begin
        # Generate name using AI
        generated_name = request_ai_name
        
        if generated_name.present? && valid_app_name?(generated_name)
          # Update app name
          old_name = @app.name
          @app.update!(name: generated_name)
          
          Rails.logger.info "[AppNamer] Successfully renamed app ##{@app.id}: '#{old_name}' → '#{generated_name}'"
          
          # Broadcast the name change to update UI
          broadcast_name_update(old_name, generated_name)
          
          return {
            success: true,
            old_name: old_name,
            new_name: generated_name,
            message: "App renamed to '#{generated_name}'"
          }
        else
          raise "Generated name is invalid: '#{generated_name}'"
        end
        
      rescue => e
        retries += 1
        Rails.logger.warn "[AppNamer] Attempt #{retries} failed: #{e.message}"
        
        if retries < MAX_RETRIES
          retry
        else
          Rails.logger.error "[AppNamer] Failed to generate name after #{MAX_RETRIES} attempts"
          return {
            success: false,
            error: e.message,
            message: "Failed to generate app name"
          }
        end
      end
    end
    
    private
    
    def extract_app_prompt
      # Get the most descriptive prompt available
      prompts = [
        @app.prompt,
        @app.description,
        @app.app_chat_messages.where(role: 'user').last&.content,
        @app.app_generations.last&.prompt
      ].compact
      
      # Use the longest, most descriptive prompt
      prompts.max_by(&:length) || "A web application"
    end
    
    def setup_ai_client
      @client_info = Ai::ModelClientFactory.create_client(NAMING_MODEL_PREFERENCE)
      Rails.logger.info "[AppNamer] Using #{@client_info[:provider]}/#{@client_info[:model]} for naming"
    end
    
    def request_ai_name
      # Create focused naming prompt
      naming_prompt = build_naming_prompt
      
      messages = [
        {
          role: "system",
          content: "You are a creative app naming expert. Generate concise, memorable names that clearly communicate the app's purpose. Return only the name, nothing else."
        },
        {
          role: "user",
          content: naming_prompt
        }
      ]
      
      # Make AI request
      response = @client_info[:client].chat(
        messages,
        model: @client_info[:model],
        temperature: 0.8,  # Higher creativity for naming
        max_tokens: 50     # Names should be short
      )
      
      if response[:success]
        # Clean up the response
        clean_name = sanitize_ai_response(response[:content])
        Rails.logger.info "[AppNamer] AI suggested: '#{clean_name}'"
        return clean_name
      else
        raise "AI naming request failed: #{response[:error]}"
      end
    end
    
    def build_naming_prompt
      # Create context-aware naming prompt
      app_type = determine_app_type
      
      prompt = <<~PROMPT
        Name this #{app_type} application based on its purpose:
        
        App Description: "#{@prompt}"
        
        Requirements:
        - 1-3 words maximum
        - Clear and descriptive
        - Professional sounding
        - Memorable and brandable
        - No generic words like "App", "Tool", "System"
        
        Examples of good names:
        - Todo app → "TaskFlow"
        - Budget tracker → "ExpenseWise"
        - Recipe manager → "ChefBook"
        - Time tracker → "TimeSync"
        - Note taking → "ThinkPad"
        
        Generate ONE perfect name:
      PROMPT
    end
    
    def determine_app_type
      # Analyze prompt to determine app category
      prompt_lower = @prompt.downcase
      
      case prompt_lower
      when /todo|task|checklist/
        "task management"
      when /budget|expense|money|finance|cost/
        "financial tracking"
      when /note|journal|diary|memo/
        "note-taking"
      when /recipe|cook|food|meal/
        "recipe management" 
      when /time|hour|schedule|calendar/
        "time management"
      when /chat|message|social/
        "communication"
      when /shop|store|ecommerce|product/
        "e-commerce"
      when /blog|article|content/
        "content management"
      when /game|play|fun/
        "gaming"
      when /learn|education|course|study/
        "educational"
      else
        "web"
      end
    end
    
    def sanitize_ai_response(raw_response)
      # Clean up AI response to get just the name
      name = raw_response.strip
      
      # Remove quotes, extra text, explanations
      name = name.gsub(/["']/, '')  # Remove quotes
      name = name.split('.').first   # Take first sentence
      name = name.split(',').first   # Take part before comma
      name = name.split(':').last    # Take part after colon
      name = name.split("\n").first  # Take first line
      
      # Remove common prefixes/suffixes
      name = name.gsub(/^(The |A |An |App |Application |Tool |System )/i, '')
      name = name.gsub(/(App|Tool|System|Application)$/i, '')
      
      # Clean whitespace and capitalize properly
      name = name.strip
      name = name.split(' ').map(&:capitalize).join(' ')
      
      name
    end
    
    def valid_app_name?(name)
      return false if name.blank?
      return false if name.length > 50
      return false if name.length < 2
      return false if name.match?(/^\d+$/)  # All numbers
      return false if name.downcase.include?('error')
      return false if name.downcase.include?('invalid')
      
      # Must contain at least one letter
      return false unless name.match?(/[a-zA-Z]/)
      
      true
    end
    
    def broadcast_name_update(old_name, new_name)
      Rails.logger.info "[AppNamer] Broadcasting name update to UI"
      
      begin
        # Broadcast to app editor to update header/title
        ActionCable.server.broadcast(
          "app_#{@app.id}_chat",
          {
            action: "name_updated",
            old_name: old_name,
            new_name: new_name,
            message: "App renamed to '#{new_name}'"
          }
        )
        
        # Update editor header via Turbo Stream
        Turbo::StreamsChannel.broadcast_replace_later_to(
          "app_#{@app.id}_editor",
          target: "app_header_name",
          html: "<h1 class='text-2xl font-bold text-gray-900'>#{new_name}</h1>"
        )
        
        # Update any other places that show app name
        Turbo::StreamsChannel.broadcast_replace_later_to(
          "app_#{@app.id}_updates",
          target: "app_#{@app.id}_name",
          html: new_name
        )
        
        # Update page title
        Turbo::StreamsChannel.broadcast_append_later_to(
          "app_#{@app.id}_editor",
          target: "head",
          html: "<script>document.title = '#{new_name} - OverSkill App Editor';</script>"
        )
        
      rescue => e
        Rails.logger.error "[AppNamer] Failed to broadcast name update: #{e.message}"
      end
    end
  end
end