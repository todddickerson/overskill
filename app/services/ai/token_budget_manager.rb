module Ai
  # Manages token budget allocation across different context types
  # Replaces hardcoded file count limits with intelligent token-aware management
  class TokenBudgetManager
    
    # Token budget allocation (30k total target)
    DEFAULT_BUDGETS = {
      system_context: 6_000,    # System prompts, tools (20%)
      template_context: 4_500,  # Base template files (15%) 
      component_context: 3_000, # UI components (10%)
      app_context: 12_000,      # App-specific files (40%)
      conversation: 3_000,      # User messages, history (10%)
      response_buffer: 1_500    # Buffer for response tokens (5%)
    }.freeze
    
    # Budget profiles for different request types
    BUDGET_PROFILES = {
      # New app generation - needs more template context
      generation: {
        system_context: 6_000,
        template_context: 7_500,   # More template context
        component_context: 4_500,  # More component context
        app_context: 6_000,        # Less app context (new app)
        conversation: 4_500,
        response_buffer: 1_500
      },
      
      # App editing - needs more app context
      editing: {
        system_context: 6_000,
        template_context: 3_000,   # Less template context
        component_context: 3_000,
        app_context: 15_000,       # More app context (editing existing)
        conversation: 1_500,       # Less conversation
        response_buffer: 1_500
      },
      
      # Component addition - balanced
      component_addition: DEFAULT_BUDGETS,
      
      # Debug/analysis - more app context, less components
      analysis: {
        system_context: 6_000,
        template_context: 1_500,
        component_context: 1_500,
        app_context: 18_000,       # Maximum app context for debugging
        conversation: 1_500,
        response_buffer: 1_500
      }
    }.freeze
    
    def initialize(request_type = :default, model = 'claude-3-sonnet')
      @request_type = request_type
      @model = model
      @token_counter = TokenCountingService.new(model)
      @budgets = BUDGET_PROFILES[request_type] || DEFAULT_BUDGETS
      @used_tokens = Hash.new(0)
      
      Rails.logger.info "[TokenBudget] Initialized for #{request_type} with #{total_budget} token budget"
    end
    
    # Get allocated budget for a context type
    def budget_for(context_type)
      @budgets[context_type] || 0
    end
    
    # Check if adding content would exceed budget for context type
    def can_add_content?(context_type, content)
      tokens_needed = @token_counter.count_tokens(content)
      remaining_budget = budget_for(context_type) - @used_tokens[context_type]
      tokens_needed <= remaining_budget
    end
    
    # Add content to a context type, tracking token usage
    def add_content(context_type, content, description = nil)
      tokens_used = @token_counter.count_tokens(content)
      
      if @used_tokens[context_type] + tokens_used > budget_for(context_type)
        Rails.logger.warn "[TokenBudget] Budget exceeded for #{context_type}: #{tokens_used} tokens (#{@used_tokens[context_type]}/#{budget_for(context_type)} used)"
        return false
      end
      
      @used_tokens[context_type] += tokens_used
      Rails.logger.debug "[TokenBudget] Added #{tokens_used} tokens to #{context_type}: #{description}" if description
      true
    end
    
    # Get remaining budget for a context type
    def remaining_budget(context_type)
      budget_for(context_type) - @used_tokens[context_type]
    end
    
    # Select files that fit within budget, prioritized by relevance
    def select_files_within_budget(files, context_type, relevance_scores = nil)
      budget = remaining_budget(context_type)
      selected_files = []
      used_tokens = 0
      
      # Sort by relevance score if provided, otherwise by file size (smaller first)
      sorted_files = if relevance_scores
        files.sort_by { |f| -(relevance_scores[f.path] || 0) }
      else
        files.sort_by { |f| f.content&.length || 0 }
      end
      
      sorted_files.each do |file|
        file_tokens = @token_counter.count_file_tokens(file.content, file.path)
        
        if used_tokens + file_tokens <= budget
          selected_files << file
          used_tokens += file_tokens
          add_content(context_type, file.content, "File: #{file.path}")
        else
          Rails.logger.debug "[TokenBudget] Skipping #{file.path} (#{file_tokens} tokens) - would exceed #{context_type} budget"
        end
      end
      
      Rails.logger.info "[TokenBudget] Selected #{selected_files.count}/#{files.count} files for #{context_type} (#{used_tokens}/#{budget} tokens)"
      selected_files
    end
    
    # Get current usage summary
    def usage_summary
      total_used = @used_tokens.values.sum
      {
        total_budget: total_budget,
        total_used: total_used,
        total_remaining: total_budget - total_used,
        utilization_percent: (total_used.to_f / total_budget * 100).round(1),
        by_context: @budgets.transform_values do |budget|
          context_type = @budgets.key(budget)
          used = @used_tokens[context_type]
          {
            budget: budget,
            used: used,
            remaining: budget - used,
            percent_used: budget > 0 ? (used.to_f / budget * 100).round(1) : 0
          }
        end
      }
    end
    
    # Check if we're close to budget limits
    def budget_warning?
      total_used = @used_tokens.values.sum
      total_used.to_f / total_budget > 0.85  # Warning at 85% usage
    end
    
    # Check if we've exceeded budget
    def budget_exceeded?
      total_used = @used_tokens.values.sum
      total_used > total_budget
    end
    
    # Get recommendations for budget optimization
    def optimization_recommendations
      recommendations = []
      
      @used_tokens.each do |context_type, used|
        budget = budget_for(context_type)
        utilization = used.to_f / budget
        
        if utilization > 0.9
          recommendations << {
            type: :over_budget,
            context: context_type,
            message: "#{context_type} is #{(utilization * 100).round}% over budget. Consider reducing content or increasing allocation."
          }
        elsif utilization < 0.3
          recommendations << {
            type: :under_utilized,
            context: context_type,
            message: "#{context_type} is only #{(utilization * 100).round}% utilized. Could reallocate tokens to other contexts."
          }
        end
      end
      
      recommendations
    end
    
    private
    
    def total_budget
      @budgets.values.sum
    end
  end
end