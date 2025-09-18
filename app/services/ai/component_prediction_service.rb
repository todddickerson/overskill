module Ai
  # Service for AI-powered component prediction and context generation
  # Optimized for Anthropic's 5-minute caching (cache_control: ephemeral)
  class ComponentPredictionService
    # Maximum components to predict and load per request
    MAX_COMPONENTS = 8

    # Component categories for better organization and prediction
    COMPONENT_CATEGORIES = {
      form: %w[button input textarea select checkbox radio-group form label],
      layout: %w[card table dialog tabs separator scroll-area sheet],
      navigation: %w[dropdown-menu menubar navigation-menu breadcrumb],
      feedback: %w[alert toast badge skeleton progress sonner],
      data: %w[avatar accordion collapsible popover tooltip hover-card],
      advanced: %w[command calendar date-picker carousel chart sidebar]
    }.freeze

    # Technical aliases for better intent matching (from ComponentRequirementsAnalyzer)
    TECHNICAL_ALIASES = {
      "crud" => %w[form table button dialog input],
      "dashboard" => %w[card chart table badge alert],
      "admin" => %w[table form dialog button badge],
      "analytics" => %w[chart card table progress],
      "ecommerce" => %w[card button badge table form],
      "blog" => %w[card button separator scroll-area],
      "landing" => %w[button card badge separator],
      "saas" => %w[card button form table alert],
      "portfolio" => %w[card button badge separator],
      "social" => %w[avatar card button dialog],
      "chat" => %w[input button card scroll-area],
      "kanban" => %w[card button badge dropdown-menu],
      "calendar" => %w[calendar card button dialog],
      "todo" => %w[checkbox button card form],
      "wizard" => %w[button card form progress],
      "settings" => %w[form select checkbox button],
      "profile" => %w[avatar form input button],
      "search" => %w[input command button card],
      "gallery" => %w[card carousel dialog button],
      "timeline" => %w[card separator button badge]
    }.freeze

    def initialize
      @token_counter = TokenCountingService.new
      @redis = Redis.new(url: Rails.application.config_for(:redis)&.dig(:url) || ENV["REDIS_URL"] || "redis://localhost:6379/1")
    rescue => e
      Rails.logger.warn "[ComponentPrediction] Redis not available: #{e.message}"
      @redis = nil
    end

    # Predict required components based on app intent and description
    def predict_components(intent, app_description = nil, app_type = "default")
      Rails.logger.info "[ComponentPrediction] Predicting components for '#{intent}' (#{app_type})"

      # Check cache first
      cache_key = component_prediction_cache_key(intent, app_description, app_type)
      cached_result = get_cached_prediction(cache_key)
      return cached_result if cached_result

      # Predict components using multiple strategies
      predicted_components = []

      # Strategy 1: Technical aliases (exact matches)
      alias_components = predict_from_aliases(intent, app_description)
      predicted_components += alias_components

      # Strategy 2: Keyword analysis (fuzzy matching)
      keyword_components = predict_from_keywords(intent, app_description)
      predicted_components += keyword_components

      # Strategy 3: App type defaults
      type_components = predict_from_app_type(app_type)
      predicted_components += type_components

      # Strategy 4: Intent pattern analysis
      pattern_components = predict_from_patterns(intent, app_description)
      predicted_components += pattern_components

      # Deduplicate and prioritize
      final_components = prioritize_and_limit_components(predicted_components, intent)

      Rails.logger.info "[ComponentPrediction] Predicted #{final_components.count} components: #{final_components.join(", ")}"

      # Cache the result
      cache_prediction(cache_key, final_components)

      final_components
    end

    # Build component context for predicted components
    def build_component_context(predicted_components, app, budget_manager)
      return "" if predicted_components.empty?

      Rails.logger.info "[ComponentPrediction] Building context for #{predicted_components.count} components"

      context = []

      # Add context header
      header = build_component_header(predicted_components)
      if budget_manager.can_add_content?(:system_context, header)
        budget_manager.add_content(:system_context, header, "Component header")
        context << header
      end

      # Load actual component files from app
      component_files = load_component_files(predicted_components, app)

      # Select components within budget
      selected_components = budget_manager.select_files_within_budget(
        component_files,
        :component_context,
        calculate_component_relevance_scores(component_files, predicted_components)
      )

      if selected_components.any?
        context << "## Predicted UI Components (5-min cached)"
        context << "Components likely needed for this request:"
        context << ""

        selected_components.each do |component_file|
          add_component_to_context(context, component_file)
        end
      end

      # Add component reference for unavailable components
      unavailable_components = predicted_components - selected_components.map { |f| extract_component_name(f.path) }
      if unavailable_components.any?
        reference_content = build_component_reference(unavailable_components)
        if budget_manager.can_add_content?(:system_context, reference_content)
          budget_manager.add_content(:system_context, reference_content, "Component reference")
          context << reference_content
        end
      end

      final_content = context.join("\n")
      tokens_used = @token_counter.count_tokens(final_content)

      Rails.logger.info "[ComponentPrediction] Built component context: #{tokens_used} tokens (#{selected_components.count} files loaded, #{unavailable_components.count} referenced)"

      final_content
    end

    # Get component prediction cache key
    def component_prediction_cache_key(intent, description, app_type)
      content = "#{intent}|#{description}|#{app_type}".downcase
      "component_prediction:#{Digest::SHA256.hexdigest(content)[0..12]}"
    end

    private

    def predict_from_aliases(intent, description)
      text = "#{intent} #{description}".downcase
      components = []

      TECHNICAL_ALIASES.each do |alias_key, alias_components|
        if text.include?(alias_key)
          components += alias_components
          Rails.logger.debug "[ComponentPrediction] Alias match '#{alias_key}' -> #{alias_components.join(", ")}"
        end
      end

      components.uniq
    end

    def predict_from_keywords(intent, description)
      text = "#{intent} #{description}".downcase
      components = []

      # Form-related keywords
      if text.match?(/form|input|submit|register|login|sign|contact/)
        components += COMPONENT_CATEGORIES[:form]
      end

      # Data display keywords
      if text.match?(/table|list|data|display|show|grid/)
        components += COMPONENT_CATEGORIES[:data] + %w[table card]
      end

      # Navigation keywords
      if text.match?(/nav|menu|route|link|breadcrumb/)
        components += COMPONENT_CATEGORIES[:navigation]
      end

      # Interactive keywords
      if text.match?(/click|button|action|interact/)
        components += %w[button dialog dropdown-menu]
      end

      # Feedback keywords
      if text.match?(/alert|message|notify|toast|error|success/)
        components += COMPONENT_CATEGORIES[:feedback]
      end

      components.uniq
    end

    def predict_from_app_type(app_type)
      case app_type.to_s.downcase
      when "dashboard", "admin"
        %w[card table chart button badge alert]
      when "ecommerce", "shop"
        %w[card button badge table form]
      when "blog", "content"
        %w[card button separator badge]
      when "landing", "marketing"
        %w[button card badge separator]
      when "social", "community"
        %w[avatar card button dialog]
      else
        %w[button card form] # Safe defaults
      end
    end

    def predict_from_patterns(intent, description)
      text = "#{intent} #{description}".downcase
      components = []

      # CRUD operations
      if text.match?(/create|add|new|edit|update|delete|manage/)
        components += %w[form button dialog table input]
      end

      # Display operations
      if text.match?(/view|show|display|list|browse/)
        components += %w[card table badge]
      end

      # Settings/configuration
      if text.match?(/setting|config|preference|option/)
        components += %w[form select checkbox button]
      end

      components.uniq
    end

    def prioritize_and_limit_components(components, intent)
      # Count component frequency (higher frequency = higher priority)
      component_counts = components.tally

      # Sort by frequency (descending) then alphabetically for consistency
      prioritized = component_counts.sort_by { |comp, count| [-count, comp] }.map(&:first)

      # Ensure essential components are included
      essential_components = %w[button card]
      prioritized = (essential_components + prioritized).uniq

      # Limit to maximum components
      limited = prioritized.take(MAX_COMPONENTS)

      Rails.logger.debug "[ComponentPrediction] Prioritized components by frequency: #{component_counts.inspect}"

      limited
    end

    def build_component_header(components)
      lines = []
      lines << ""
      lines << "## AI-Predicted Components"
      lines << "Based on intent analysis, these components are predicted to be needed:"
      lines << ""
      lines << "**Predicted**: #{components.map { |c| "`#{c}`" }.join(", ")}"
      lines << "**Strategy**: Technical aliases + keyword analysis + pattern matching"
      lines << ""

      lines.join("\n")
    end

    def load_component_files(component_names, app)
      files = []

      component_names.each do |component_name|
        component_path = "src/components/ui/#{component_name}.tsx"
        component_file = app&.app_files&.find_by(path: component_path)

        if component_file
          files << component_file
        else
          Rails.logger.debug "[ComponentPrediction] Component file not found: #{component_path}"
        end
      end

      Rails.logger.info "[ComponentPrediction] Loaded #{files.count}/#{component_names.count} component files"
      files
    end

    def add_component_to_context(context, component_file)
      component_name = extract_component_name(component_file.path)

      context << "### #{component_name} Component"
      context << "`#{component_file.path}`"
      context << ""
      context << "```typescript"

      # Add line numbers for consistency
      numbered_content = component_file.content.lines.map.with_index(1) do |line, num|
        "#{num.to_s.rjust(4)}: #{line}"
      end.join

      context << numbered_content.rstrip
      context << "```"
      context << ""
    end

    def build_component_reference(component_names)
      lines = []
      lines << ""
      lines << "## Additional Available Components"
      lines << "These components are available but not loaded (use on-demand loading):"
      lines << ""

      component_names.each do |component_name|
        lines << "• **#{component_name}**: `import { #{component_name.camelize} } from \"@/components/ui/#{component_name}\"`"
      end

      lines << ""

      lines.join("\n")
    end

    def calculate_component_relevance_scores(component_files, predicted_components)
      scores = {}

      component_files.each do |file|
        component_name = extract_component_name(file.path)

        # Higher score for components that were specifically predicted
        score = predicted_components.include?(component_name) ? 3.0 : 1.0

        # Boost score for commonly used components
        if %w[button card form].include?(component_name)
          score *= 1.5
        end

        # Lower score for very large components
        if file.content && file.content.length > 5000  # Large component
          score *= 0.7
        end

        scores[file.path] = score
      end

      scores
    end

    def extract_component_name(file_path)
      File.basename(file_path, ".tsx")
    end

    def get_cached_prediction(cache_key)
      return nil unless @redis

      begin
        cached = @redis.get(cache_key)
        if cached
          result = JSON.parse(cached)
          Rails.logger.debug "[ComponentPrediction] Cache hit for #{cache_key}"
          return result
        end
      rescue => e
        Rails.logger.warn "[ComponentPrediction] Cache read error: #{e.message}"
      end

      nil
    end

    def cache_prediction(cache_key, components)
      return unless @redis

      begin
        @redis.setex(cache_key, 5.minutes.to_i, components.to_json)
        Rails.logger.debug "[ComponentPrediction] Cached prediction for #{cache_key}"
      rescue => e
        Rails.logger.warn "[ComponentPrediction] Cache write error: #{e.message}"
      end
    end
  end
end
