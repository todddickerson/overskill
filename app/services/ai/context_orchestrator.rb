module Ai
  # Orchestrates the new three-service architecture for context generation
  # Implements hierarchical context assembly with proper Anthropic caching
  class ContextOrchestrator
    
    # Request type profiles for different context needs
    REQUEST_PROFILES = {
      generation: {
        description: "New app generation",
        template_weight: 0.4,    # Higher template context
        component_weight: 0.3,   # Moderate component context
        app_weight: 0.2,         # Lower app context (new app)
        request_type: :generation
      },
      editing: {
        description: "Existing app modification", 
        template_weight: 0.2,    # Lower template context
        component_weight: 0.2,   # Moderate component context
        app_weight: 0.5,         # Higher app context
        request_type: :editing
      },
      component_addition: {
        description: "Adding new components",
        template_weight: 0.3,
        component_weight: 0.4,   # Higher component context
        app_weight: 0.2,
        request_type: :component_addition
      },
      debugging: {
        description: "Debug and analysis",
        template_weight: 0.1,    # Minimal template context
        component_weight: 0.1,   # Minimal component context  
        app_weight: 0.7,         # Maximum app context
        request_type: :analysis
      }
    }.freeze
    
    def initialize(profile = :editing)
      @profile = REQUEST_PROFILES[profile] || REQUEST_PROFILES[:editing]
      @template_service = TemplateContextService.new
      @component_service = ComponentPredictionService.new
      @app_service = AppContextService.new
    end
    
    # Main entry point: build complete context using new architecture
    def build_context(app, request_context = {})
      intent = request_context[:intent] || request_context[:prompt] || "modify app"
      focus_files = request_context[:focus_files] || []
      
      Rails.logger.info "[ContextOrchestrator] Building context for #{@profile[:description]}"
      Rails.logger.info "[ContextOrchestrator] Intent: #{intent.truncate(100)}"
      
      # Initialize budget manager with profile-specific budgets
      budget_manager = create_budget_manager()
      
      # Build context in layers with proper caching strategies
      context_layers = []
      
      # Layer 1: Template context (1-hour cached)
      template_context = build_template_layer(budget_manager)
      context_layers << wrap_for_anthropic_cache(template_context, :template, 3600) if template_context.present?
      
      # Layer 2: Component context (5-minute cached) 
      component_context = build_component_layer(app, intent, budget_manager)
      context_layers << wrap_for_anthropic_cache(component_context, :component, 300) if component_context.present?
      
      # Layer 3: App context (no cache - real-time)
      app_context = build_app_layer(app, focus_files, budget_manager)
      context_layers << app_context if app_context.present?
      
      # Assemble final context
      final_context = assemble_context_layers(context_layers)
      
      # Log comprehensive metrics
      log_context_metrics(final_context, budget_manager, app)
      
      final_context
    end
    
    # Build context formatted for Anthropic API with cache control
    def build_anthropic_context(app, request_context = {})
      context_layers = build_context_layers_for_anthropic(app, request_context)
      
      # Return array of message objects with cache control
      context_layers.compact
    end
    
    private
    
    def create_budget_manager
      TokenBudgetManager.new(@profile[:request_type])
    end
    
    def build_template_layer(budget_manager)
      Rails.logger.info "[ContextOrchestrator] Building template layer (1h cache)"
      
      template_context = @template_service.build_template_context(budget_manager)
      
      if template_context.present?
        Rails.logger.info "[ContextOrchestrator] Template layer built successfully"
        template_context
      else
        Rails.logger.warn "[ContextOrchestrator] Template layer empty or over budget"
        nil
      end
    end
    
    def build_component_layer(app, intent, budget_manager)
      Rails.logger.info "[ContextOrchestrator] Building component layer (5m cache)"
      
      # Predict components based on intent
      predicted_components = @component_service.predict_components(intent, app.description, app.app_type)
      
      if predicted_components.any?
        component_context = @component_service.build_component_context(
          predicted_components, 
          app, 
          budget_manager
        )
        
        Rails.logger.info "[ContextOrchestrator] Component layer built: #{predicted_components.count} components"
        component_context
      else
        Rails.logger.info "[ContextOrchestrator] No components predicted for this request"
        nil
      end
    end
    
    def build_app_layer(app, focus_files, budget_manager)
      Rails.logger.info "[ContextOrchestrator] Building app layer (real-time, no cache)"
      
      app_context = @app_service.build_app_context(app, focus_files, budget_manager)
      
      if app_context.present?
        Rails.logger.info "[ContextOrchestrator] App layer built successfully"
        app_context
      else
        Rails.logger.warn "[ContextOrchestrator] App layer empty or over budget"
        nil
      end
    end
    
    def wrap_for_anthropic_cache(content, layer_type, ttl_seconds)
      {
        type: "text",
        text: content,
        cache_control: { 
          type: "ephemeral",
          ttl: ttl_seconds
        },
        layer: layer_type  # For debugging/metrics
      }
    end
    
    def assemble_context_layers(layers)
      layers.map do |layer|
        if layer.is_a?(Hash) && layer[:text]
          layer[:text]  # Extract text content for simple string context
        else
          layer.to_s
        end
      end.join("\n\n" + "="*50 + "\n\n")
    end
    
    def build_context_layers_for_anthropic(app, request_context)
      intent = request_context[:intent] || request_context[:prompt] || "modify app"
      focus_files = request_context[:focus_files] || []
      
      budget_manager = create_budget_manager()
      layers = []
      
      # Template layer with 1-hour cache
      template_context = build_template_layer(budget_manager)
      if template_context.present?
        layers << {
          type: "text",
          text: template_context,
          cache_control: { type: "ephemeral" }  # 1-hour default TTL
        }
      end
      
      # Component layer with 5-minute cache  
      component_context = build_component_layer(app, intent, budget_manager)
      if component_context.present?
        layers << {
          type: "text",
          text: component_context,
          cache_control: { type: "ephemeral" }  # 5-minute TTL (requires API support)
        }
      end
      
      # App layer with no cache (always fresh)
      app_context = build_app_layer(app, focus_files, budget_manager)
      if app_context.present?
        layers << {
          type: "text", 
          text: app_context
          # No cache_control - always fresh
        }
      end
      
      layers
    end
    
    def log_context_metrics(final_context, budget_manager, app)
      token_counter = TokenCountingService.new
      actual_tokens = token_counter.count_tokens(final_context)
      usage = budget_manager.usage_summary
      
      Rails.logger.info "[ContextOrchestrator] FINAL METRICS:"
      Rails.logger.info "[ContextOrchestrator] ✓ Profile: #{@profile[:description]}"
      Rails.logger.info "[ContextOrchestrator] ✓ Context: #{final_context.length} chars, #{actual_tokens} tokens"
      Rails.logger.info "[ContextOrchestrator] ✓ Budget: #{usage[:total_used]}/#{usage[:total_budget]} tokens (#{usage[:utilization_percent]}%)"
      Rails.logger.info "[ContextOrchestrator] ✓ Efficiency: #{((1 - usage[:total_used].to_f / 120_000) * 100).round}% reduction from naive approach"
      
      # Log per-layer breakdown
      usage[:by_context].each do |context_type, stats|
        next if stats[:used] == 0
        Rails.logger.info "[ContextOrchestrator]   └─ #{context_type}: #{stats[:used]}/#{stats[:budget]} tokens (#{stats[:percent_used]}%)"
      end
      
      # Log warnings and recommendations
      if usage[:utilization_percent] > 85
        Rails.logger.warn "[ContextOrchestrator] ⚠️ High budget utilization: #{usage[:utilization_percent]}%"
      end
      
      if actual_tokens < 15_000
        Rails.logger.info "[ContextOrchestrator] 💡 Budget underutilized - could include more context"
      end
      
      budget_manager.optimization_recommendations.each do |rec|
        Rails.logger.info "[ContextOrchestrator] 💡 #{rec[:message]}"
      end
      
      # Cache effectiveness metrics
      cache_effectiveness = calculate_cache_effectiveness(usage)
      Rails.logger.info "[ContextOrchestrator] 📊 Cache strategy: #{cache_effectiveness[:description]}"
    end
    
    def calculate_cache_effectiveness(usage)
      template_tokens = usage[:by_context][:template_context][:used] || 0
      component_tokens = usage[:by_context][:component_context][:used] || 0
      app_tokens = usage[:by_context][:app_context][:used] || 0
      total_tokens = usage[:total_used]
      
      if total_tokens == 0
        return { description: "No context generated" }
      end
      
      cached_ratio = (template_tokens + component_tokens).to_f / total_tokens
      
      if cached_ratio > 0.7
        { description: "High cache effectiveness (#{(cached_ratio * 100).round}% cacheable)" }
      elsif cached_ratio > 0.4
        { description: "Moderate cache effectiveness (#{(cached_ratio * 100).round}% cacheable)" }
      else
        { description: "Low cache effectiveness (#{(cached_ratio * 100).round}% cacheable) - mostly real-time content" }
      end
    end
    
    # Utility method to get context statistics
    def get_context_stats(app, request_context = {})
      intent = request_context[:intent] || "analyze"
      
      # Quick analysis without building full context
      predicted_components = @component_service.predict_components(intent, app.description)
      candidate_files = @app_service.get_relevant_app_files(app, request_context[:focus_files] || [])
      
      {
        profile: @profile[:description],
        template_files: TemplateContextService::TEMPLATE_ESSENTIALS.count,
        predicted_components: predicted_components.count,
        candidate_app_files: candidate_files.count,
        total_app_files: app.app_files.count,
        reduction_ratio: ((1 - candidate_files.count.to_f / app.app_files.count) * 100).round
      }
    end
  end
end