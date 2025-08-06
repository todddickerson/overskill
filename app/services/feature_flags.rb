# FeatureFlags - Centralized feature flag management
# Allows gradual rollout of new features and A/B testing
class FeatureFlags
  class << self
    # Check if unified AI system should be used
    def use_unified_ai?(app: nil, user: nil, team: nil)
      # Environment override - useful for testing
      return true if ENV['FORCE_UNIFIED_AI'] == 'true'
      return false if ENV['FORCE_UNIFIED_AI'] == 'false'
      
      # Gradual rollout by percentage
      if ENV['UNIFIED_AI_ROLLOUT_PERCENT'].present?
        percentage = ENV['UNIFIED_AI_ROLLOUT_PERCENT'].to_i
        return rollout_by_percentage(app&.id || user&.id || team&.id, percentage)
      end
      
      # Rollout by app type
      if app && ENV['UNIFIED_AI_APP_TYPES'].present?
        enabled_types = ENV['UNIFIED_AI_APP_TYPES'].split(',')
        return enabled_types.include?(app.app_type)
      end
      
      # Rollout by team
      if team && ENV['UNIFIED_AI_TEAM_IDS'].present?
        enabled_teams = ENV['UNIFIED_AI_TEAM_IDS'].split(',').map(&:to_i)
        return enabled_teams.include?(team.id)
      end
      
      # Default behavior from environment
      ENV['USE_UNIFIED_AI'] != 'false'
    end
    
    # Check if we should use the new orchestrator
    def use_ai_orchestrator_v2?
      ENV['USE_AI_ORCHESTRATOR'] == 'true'
    end
    
    # Check if we should use streaming updates
    def use_streaming_updates?(app: nil)
      return false if ENV['DISABLE_STREAMING'] == 'true'
      
      # Can be more granular based on app
      if app && app.framework == 'react'
        # React apps might benefit more from streaming
        return true
      end
      
      ENV['USE_STREAMING_UPDATES'] != 'false'
    end
    
    # Check if enhanced error handling is enabled
    def enhanced_error_handling?
      ENV['ENHANCED_ERROR_HANDLING'] != 'false'
    end
    
    # Check if we should show TODO tracking to users
    def show_todo_tracking?(user: nil, team: nil)
      # Always show for admins
      return true if user&.admin?
      
      # Gradual rollout
      if ENV['TODO_TRACKING_ROLLOUT_PERCENT'].present?
        percentage = ENV['TODO_TRACKING_ROLLOUT_PERCENT'].to_i
        return rollout_by_percentage(user&.id || team&.id, percentage)
      end
      
      ENV['SHOW_TODO_TRACKING'] != 'false'
    end
    
    # Check if we should use Claude 4 as primary model
    def use_claude_4?
      ENV['USE_CLAUDE_4'] != 'false'
    end
    
    # Check if we should enable database features
    def database_features_enabled?(app: nil)
      return false if ENV['DISABLE_DATABASE_FEATURES'] == 'true'
      
      # Can check if app has database tables
      if app
        return app.app_tables.any?
      end
      
      ENV['ENABLE_DATABASE_FEATURES'] == 'true'
    end
    
    private
    
    # Deterministic rollout based on ID and percentage
    def rollout_by_percentage(id, percentage)
      return false unless id && percentage
      
      # Use consistent hashing for deterministic results
      hash = Digest::MD5.hexdigest("unified_ai_#{id}").to_i(16)
      (hash % 100) < percentage
    end
  end
end