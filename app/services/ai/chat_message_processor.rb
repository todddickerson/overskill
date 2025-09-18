module Ai
  class ChatMessageProcessor
    # The heart of our Lovable.dev/Bolt.new competitor
    # Handles ongoing user conversations to iteratively build and modify apps

    def initialize(app_chat_message)
      @app = app_chat_message.app
      @message = app_chat_message
      @user = app_chat_message.user
      @context = build_conversation_context
    end

    def process!
      Rails.logger.info "[ChatProcessor] Processing message for app ##{@app.id}: #{@message.content.truncate(100)}"

      # 1. Classify the message type and intent
      message_analysis = classify_message_intent
      Rails.logger.info "[ChatProcessor] Message classified as: #{message_analysis[:type]} (confidence: #{message_analysis[:confidence]})"

      # 2. Analyze current app state and files
      app_context = analyze_current_app_state
      Rails.logger.info "[ChatProcessor] App context: #{app_context[:existing_components].keys.count} components, #{app_context[:file_structure][:total_files]} files"

      # 3. Determine appropriate action
      action_plan = generate_action_plan(message_analysis, app_context)
      Rails.logger.info "[ChatProcessor] Generated #{action_plan[:steps].count} step action plan"

      # 4. Execute the changes
      execution_result = execute_changes(action_plan)

      # 5. Update preview and provide feedback
      response = update_preview_and_respond(execution_result, action_plan)

      Rails.logger.info "[ChatProcessor] Processing complete for app ##{@app.id}"
      response
    rescue => e
      Rails.logger.error "[ChatProcessor] Processing failed for app ##{@app.id}: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")

      create_error_response(e)
    end

    private

    MESSAGE_TYPES = {
      initial_generation: /^(create|build|generate|make)\s+.*app/i,
      add_feature: /^(add|include|implement)\s+/i,
      modify_feature: /^(change|update|modify|edit)\s+/i,
      fix_bug: /^(fix|debug|resolve|correct)\s+/i,
      style_change: /^(style|design|color|theme|make.*look|change.*appearance)\s+/i,
      component_request: /^(use|add).*component/i,
      deployment_request: /^(deploy|publish|launch)\s+/i,
      question: /^(how|what|why|when|where)\s+/i,
      remove_feature: /^(remove|delete|take away|get rid of)\s+/i
    }.freeze

    def classify_message_intent
      content = @message.content.downcase

      # Determine primary message type
      message_type = MESSAGE_TYPES.find { |type, pattern| content.match?(pattern) }&.first || :general_request

      # Extract specific entities (components, files, features)
      entities = extract_entities(content)

      # Determine urgency and scope
      scope = determine_change_scope(content)

      # Calculate confidence based on pattern matching and context
      confidence = calculate_confidence(content, message_type)

      {
        type: message_type,
        entities: entities,
        scope: scope,
        urgency: classify_urgency(content),
        confidence: confidence,
        raw_content: @message.content
      }
    end

    def extract_entities(content)
      entities = {
        components: [],
        features: [],
        files: [],
        colors: [],
        ui_elements: []
      }

      # Extract UI component mentions
      ui_components = %w[button input form table card modal dialog dropdown menu navigation header footer sidebar]
      entities[:ui_elements] = ui_components.select { |component| content.include?(component) }

      # Extract feature mentions
      features = %w[authentication auth login signup chat messaging todo task dashboard analytics upload download search filter sort]
      entities[:features] = features.select { |feature| content.include?(feature) }

      # Extract file mentions (src/components/ComponentName.tsx pattern)
      file_mentions = content.scan(/src\/[\w\/]+\.\w+/)
      entities[:files] = file_mentions

      # Extract color mentions
      colors = %w[red green blue yellow purple pink orange gray grey black white primary secondary]
      entities[:colors] = colors.select { |color| content.include?(color) }

      entities
    end

    def determine_change_scope(content)
      # Analyze scope of changes needed
      if content.match?(/entire|whole|all|everything/)
        :major
      elsif content.match?(/component|page|file/)
        :moderate
      elsif content.match?(/style|color|text|size/)
        :minor
      else
        :moderate
      end
    end

    def classify_urgency(content)
      if content.match?(/urgent|asap|quickly|now|immediately/)
        :high
      elsif content.match?(/when you can|later|eventually/)
        :low
      else
        :normal
      end
    end

    def calculate_confidence(content, message_type)
      confidence = 0.5

      # Boost confidence for clear patterns
      if MESSAGE_TYPES[message_type] && content.match?(MESSAGE_TYPES[message_type])
        confidence += 0.3
      end

      # Boost confidence for specific entity mentions
      if content.match?(/component|file|feature|style/)
        confidence += 0.1
      end

      # Reduce confidence for vague requests
      if content.match?(/maybe|perhaps|might|could|possibly/)
        confidence -= 0.2
      end

      [confidence, 1.0].min
    end

    def build_conversation_context
      # Get recent messages in this conversation
      recent_messages = @app.app_chat_messages
        .where("created_at >= ?", 1.day.ago)
        .order(created_at: :desc)
        .limit(10)

      {
        recent_messages: recent_messages,
        app_status: @app.status,
        last_generation: @app.app_versions.last,
        user_patterns: analyze_user_communication_patterns
      }
    end

    def analyze_user_communication_patterns
      # Analyze how this user typically communicates
      user_messages = AppChatMessage.joins(:app)
        .where(user: @user, role: "user")
        .limit(50)

      {
        total_messages: user_messages.count,
        avg_message_length: user_messages.average("LENGTH(content)") || 0,
        common_request_types: extract_common_patterns(user_messages)
      }
    end

    def extract_common_patterns(messages)
      patterns = Hash.new(0)

      messages.find_each do |message|
        MESSAGE_TYPES.each do |type, pattern|
          if message.content.downcase.match?(pattern)
            patterns[type] += 1
          end
        end
      end

      patterns.sort_by { |_, count| -count }.first(3).to_h
    end

    def analyze_current_app_state
      # Delegate to FileContextAnalyzer for detailed analysis
      Ai::FileContextAnalyzer.new(@app).analyze
    end

    def generate_action_plan(message_analysis, app_context)
      # Delegate to ActionPlanGenerator for intelligent planning
      Ai::ActionPlanGenerator.new(@app, @message, message_analysis, app_context).generate
    end

    def execute_changes(action_plan)
      Rails.logger.info "[ChatProcessor] Executing action plan with #{action_plan[:steps].count} steps"

      results = []

      action_plan[:steps].each_with_index do |step, index|
        Rails.logger.info "[ChatProcessor] Executing step #{index + 1}: #{step[:action]}"

        step_result = execute_step(step)
        results << step_result

        # Break on critical failures
        if step_result[:success] == false && step[:critical] == true
          Rails.logger.error "[ChatProcessor] Critical step failed, stopping execution"
          break
        end
      end

      {
        success: results.any? { |r| r[:success] },
        step_results: results,
        files_changed: results.map { |r| r[:files_changed] }.flatten.compact,
        total_steps: results.count,
        successful_steps: results.count { |r| r[:success] }
      }
    end

    def execute_step(step)
      case step[:action]
      when :modify_files
        execute_file_modifications(step)
      when :add_files
        execute_file_additions(step)
      when :suggest_components
        execute_component_suggestions(step)
      when :add_dependencies
        execute_dependency_additions(step)
      when :update_routing
        execute_routing_updates(step)
      when :apply_styling
        execute_styling_changes(step)
      else
        Rails.logger.warn "[ChatProcessor] Unknown action: #{step[:action]}"
        {success: false, error: "Unknown action: #{step[:action]}"}
      end
    rescue => e
      Rails.logger.error "[ChatProcessor] Step execution failed: #{e.message}"
      {success: false, error: e.message}
    end

    def execute_file_modifications(step)
      changed_files = []

      step[:files].each do |file_spec|
        file = @app.app_files.find_by(path: file_spec[:path])

        if file
          # Use LineReplaceService for surgical edits
          result = if file_spec[:changes][:type] == :line_replace
            apply_line_replacement(file, file_spec[:changes])
          else
            # Direct content replacement for simple changes
            apply_content_replacement(file, file_spec[:changes])
          end
          changed_files << file.path if result[:success]
        else
          Rails.logger.warn "[ChatProcessor] File not found: #{file_spec[:path]}"
        end
      end

      {
        success: changed_files.any?,
        files_changed: changed_files,
        message: "Modified #{changed_files.count} files"
      }
    end

    def execute_file_additions(step)
      created_files = []

      step[:files].each do |file_spec|
        # Generate content using Claude if needed
        content = file_spec[:content] || generate_file_content(file_spec)

        # Create the file
        file = @app.app_files.create!(
          path: file_spec[:path],
          content: content,
          team: @app.team
        )

        created_files << file.path
        Rails.logger.info "[ChatProcessor] Created file: #{file.path}"
      end

      {
        success: created_files.any?,
        files_changed: created_files,
        message: "Created #{created_files.count} files"
      }
    end

    def execute_component_suggestions(step)
      # Add suggested components to the app
      component_service = Ai::EnhancedOptionalComponentService.new(@app)

      components_added = []

      step[:components].each do |component_suggestion|
        if component_suggestion[:type] == :exact_match
          component_suggestion[:components].each do |component|
            result = component_service.add_component_category(component)
            components_added << component if result
          end
        end
      end

      {
        success: components_added.any?,
        files_changed: [], # Components create their own files
        message: "Added #{components_added.count} component categories",
        components_added: components_added
      }
    end

    def execute_dependency_additions(step)
      return {success: true, message: "No dependencies to add"} unless step[:packages]&.any?

      # Update package.json with new dependencies
      package_file = @app.app_files.find_by(path: "package.json")
      return {success: false, error: "package.json not found"} unless package_file

      begin
        package_json = JSON.parse(package_file.content)
        package_json["dependencies"] ||= {}

        added_packages = []
        step[:packages].each do |package|
          unless package_json["dependencies"].key?(package)
            package_json["dependencies"][package] = "latest"
            added_packages << package
          end
        end

        if added_packages.any?
          package_file.update!(content: JSON.pretty_generate(package_json))
        end

        {
          success: true,
          files_changed: added_packages.any? ? ["package.json"] : [],
          message: "Added #{added_packages.count} dependencies",
          packages_added: added_packages
        }
      rescue JSON::ParserError => e
        Rails.logger.error "[ChatProcessor] Failed to parse package.json: #{e.message}"
        {success: false, error: "Invalid package.json format"}
      end
    end

    def execute_routing_updates(step)
      return {success: true, message: "No routing updates needed"} unless step[:routes]&.any?

      router_file = @app.app_files.find_by(path: "src/router.tsx")
      return {success: false, error: "Router file not found"} unless router_file

      # Use LineReplaceService to add new routes
      routes_added = []

      step[:routes].each do |route|
        # Generate route code
        route_code = generate_route_code(route)

        # Add route to router using line replacement
        result = add_route_to_router(router_file, route_code)
        routes_added << route[:path] if result[:success]
      end

      {
        success: routes_added.any?,
        files_changed: routes_added.any? ? ["src/router.tsx"] : [],
        message: "Added #{routes_added.count} routes",
        routes_added: routes_added
      }
    end

    def execute_styling_changes(step)
      # Apply styling changes to components
      changed_files = []

      step[:style_changes].each do |change|
        file = @app.app_files.find_by(path: change[:file])
        next unless file

        # Apply CSS/Tailwind class changes
        result = apply_styling_to_file(file, change[:modifications])
        changed_files << file.path if result[:success]
      end

      {
        success: changed_files.any?,
        files_changed: changed_files,
        message: "Applied styling to #{changed_files.count} files"
      }
    end

    def update_preview_and_respond(execution_result, action_plan)
      response = {
        success: execution_result[:success],
        message: build_response_message(execution_result, action_plan),
        files_changed: execution_result[:files_changed],
        preview_updated: false
      }

      # Update preview if files were changed
      if execution_result[:files_changed].any?
        preview_result = update_live_preview(execution_result[:files_changed])
        response[:preview_updated] = preview_result[:success]
        response[:preview_url] = preview_result[:preview_url] if preview_result[:success]
        response[:build_time] = preview_result[:build_time]
      end

      # Create response message in chat
      create_response_message(response)

      response
    end

    def update_live_preview(changed_files)
      # Use LivePreviewManager for real-time updates
      Ai::LivePreviewManager.new(@app).update_preview_after_changes(changed_files)
    rescue => e
      Rails.logger.error "[ChatProcessor] Preview update failed: #{e.message}"
      {success: false, error: e.message}
    end

    def build_response_message(execution_result, action_plan)
      if execution_result[:success]
        messages = []
        messages << "✅ Successfully completed #{execution_result[:successful_steps]}/#{execution_result[:total_steps]} steps"

        if execution_result[:files_changed].any?
          messages << "📝 Modified #{execution_result[:files_changed].count} files: #{execution_result[:files_changed].join(", ")}"
        end

        messages << action_plan[:summary] if action_plan[:summary]
        messages.join("\n")
      else
        "❌ Failed to complete the requested changes. Please check the specific requirements and try again."
      end
    end

    def create_response_message(response)
      @app.app_chat_messages.create!(
        role: "assistant",
        content: response[:message],
        user: @user,
        metadata: {
          chat_processor_response: true,
          files_changed: response[:files_changed],
          preview_updated: response[:preview_updated],
          preview_url: response[:preview_url],
          processing_time: Time.current.iso8601
        }.to_json
      )
    end

    def create_error_response(error)
      error_message = "I encountered an error while processing your request: #{error.message}. Please try rephrasing your request or contact support if the issue persists."

      @app.app_chat_messages.create!(
        role: "assistant",
        content: error_message,
        user: @user,
        metadata: {
          error: true,
          error_class: error.class.name,
          error_message: error.message
        }.to_json
      )

      {
        success: false,
        error: error.message,
        message: error_message
      }
    end

    # Utility methods for specific operations

    def apply_line_replacement(file, changes)
      # Integrate with existing LineReplaceService
      line_replace_service = Ai::LineReplaceService.new

      result = line_replace_service.replace_lines(
        file: file,
        search_pattern: changes[:search_pattern],
        replacement: changes[:replacement],
        context: changes[:context] || {}
      )

      {success: result[:success]}
    rescue => e
      Rails.logger.error "[ChatProcessor] Line replacement failed: #{e.message}"
      {success: false, error: e.message}
    end

    def apply_content_replacement(file, changes)
      # Simple content replacement for basic changes
      updated_content = file.content.gsub(changes[:find], changes[:replace])

      if updated_content != file.content
        file.update!(content: updated_content)
        {success: true}
      else
        Rails.logger.warn "[ChatProcessor] No changes made to #{file.path} - pattern not found"
        {success: false, error: "Pattern not found in file"}
      end
    rescue => e
      Rails.logger.error "[ChatProcessor] Content replacement failed: #{e.message}"
      {success: false, error: e.message}
    end

    def generate_file_content(file_spec)
      # Generate file content using Claude
      prompt = build_file_generation_prompt(file_spec)

      # Use existing Claude integration
      client = Ai::AnthropicClient.instance
      response = client.chat(
        [{role: "user", content: prompt}],
        model: :claude_sonnet_4,
        temperature: 0.3,
        max_tokens: 4000
      )

      extract_code_from_response(response[:content])
    rescue => e
      Rails.logger.error "[ChatProcessor] File content generation failed: #{e.message}"
      "// Generated file placeholder\n// TODO: Implement #{file_spec[:purpose]}"
    end

    def build_file_generation_prompt(file_spec)
      <<~PROMPT
        Generate a #{file_spec[:type]} file for #{file_spec[:purpose]}.
        
        File path: #{file_spec[:path]}
        Requirements: #{file_spec[:requirements]&.join(", ")}
        
        Follow these guidelines:
        - Use TypeScript and React
        - Follow existing project patterns
        - Use Tailwind CSS for styling
        - Import necessary dependencies
        - Make it production-ready
        
        Return only the code without explanations.
      PROMPT
    end

    def extract_code_from_response(content)
      # Extract code from Claude response, similar to existing pattern
      code_match = content.match(/```(?:typescript|tsx|ts|jsx|js)?\n(.*?)```/m)

      if code_match
        code_match[1].strip
      else
        # Fallback if no code block found
        content.strip
      end
    end
  end
end
