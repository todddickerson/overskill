module Ai
  # Intelligently selects AI provider based on capabilities, cost, and reliability
  class ProviderSelectorService
    
    def self.select_for_task(task_type, options = {})
      case task_type
      when :tool_calling
        select_tool_calling_provider(options)
      when :app_generation
        select_generation_provider(options)
      when :quick_tasks
        select_quick_provider(options)
      else
        select_default_provider(options)
      end
    end
    
    def self.tool_calling_available_via_openrouter?
      # Check feature flag and recent test results
      flag = FeatureFlag.find_by(name: 'openrouter_kimi_tool_calling')
      return false unless flag&.enabled?
      
      # Check if recent tests indicate it's working
      recent_test_file = Rails.root.join('log', 'tool_calling_tests', 'latest_result.json')
      if File.exist?(recent_test_file)
        begin
          result = JSON.parse(File.read(recent_test_file))
          return result['success'] && result['timestamp'] > 7.days.ago.to_i
        rescue JSON::ParserError
          return false
        end
      end
      
      false
    end
    
    def self.select_tool_calling_provider(options = {})
      user = options[:user]
      
      if tool_calling_available_via_openrouter?
        # Check if user is in rollout percentage
        if user && FeatureFlag.enabled?('openrouter_kimi_tool_calling', user_id: user.id)
          {
            provider: :openrouter,
            client_class: Ai::OpenRouterClient,
            cost_multiplier: 1.0,
            reason: "OpenRouter tool calling available and user in rollout"
          }
        else
          # Fall back to Moonshot for users not in rollout
          {
            provider: :moonshot_direct,
            client_class: Ai::MoonshotDirectClient,
            cost_multiplier: 28.0,
            reason: "OpenRouter works but user not in rollout - using Moonshot"
          }
        end
      else
        # OpenRouter tool calling not working, use Moonshot Direct
        {
          provider: :moonshot_direct,
          client_class: Ai::MoonshotDirectClient,
          cost_multiplier: 28.0,
          reason: "OpenRouter tool calling unavailable - using reliable Moonshot Direct"
        }
      end
    end
    
    def self.select_generation_provider(options = {})
      # For app generation, prefer reliability over cost
      model_preference = options[:model] || :kimi_k2
      
      case model_preference
      when :kimi_k2
        if tool_calling_available_via_openrouter?
          {
            provider: :openrouter,
            client_class: Ai::OpenRouterClient,
            cost_multiplier: 1.0,
            reason: "OpenRouter available for K2 generation"
          }
        else
          {
            provider: :moonshot_direct,
            client_class: Ai::MoonshotDirectClient,
            cost_multiplier: 28.0,
            reason: "Moonshot Direct for reliable K2 generation"
          }
        end
      when :claude_sonnet
        {
          provider: :openrouter,
          client_class: Ai::OpenRouterClient,
          cost_multiplier: 170.0,
          reason: "Claude Sonnet for high-quality generation (expensive)"
        }
      else
        select_default_provider(options)
      end
    end
    
    def self.select_quick_provider(options = {})
      # For quick tasks, prefer cost efficiency
      {
        provider: :openrouter,
        client_class: Ai::OpenRouterClient,
        cost_multiplier: 1.0,
        reason: "OpenRouter for cost-efficient quick tasks"
      }
    end
    
    def self.select_default_provider(options = {})
      # Default to OpenRouter for general tasks
      {
        provider: :openrouter,
        client_class: Ai::OpenRouterClient,
        cost_multiplier: 1.0,
        reason: "OpenRouter default provider"
      }
    end
    
    def self.create_client(provider_info)
      provider_info[:client_class].new
    end
    
    def self.log_provider_selection(task_type, provider_info, user_id = nil)
      Rails.logger.info "[AI Provider] #{task_type} -> #{provider_info[:provider]} (#{provider_info[:reason]}) Cost: #{provider_info[:cost_multiplier]}x#{user_id ? " User: #{user_id}" : ""}"
    end
  end
end