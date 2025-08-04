module Deployment
  class EnvironmentVariablesService
    def initialize(app)
      @app = app
    end
    
    def to_env_hash
      env_vars = {}
      
      # Add common React/JS environment variables
      @app.app_settings.each do |setting|
        # React apps expect REACT_APP_ prefix for custom variables
        key = if setting.key.start_with?('REACT_APP_')
                setting.key
              else
                "REACT_APP_#{setting.key}"
              end
        
        # Only include non-encrypted values or handle encrypted ones securely
        value = setting.encrypted? ? decrypt_value(setting) : setting.value
        env_vars[key] = value if value.present?
      end
      
      # Add default environment variables
      env_vars.merge!(default_env_vars)
      
      env_vars
    end
    
    def to_env_file
      to_env_hash.map { |k, v| "#{k}=#{v}" }.join("\n")
    end
    
    def to_cloudflare_format
      # Cloudflare Workers expect environment variables in a specific format
      {
        compatibility_date: Date.current.to_s,
        vars: to_env_hash
      }
    end
    
    private
    
    def default_env_vars
      {
        'NODE_ENV' => Rails.env.production? ? 'production' : 'development',
        'PUBLIC_URL' => @app.preview_url || '/',
        'REACT_APP_API_URL' => api_url_for_app,
        'REACT_APP_SUPABASE_URL' => supabase_url,
        'REACT_APP_SUPABASE_ANON_KEY' => supabase_anon_key
      }
    end
    
    def api_url_for_app
      # Return the API URL for the app's backend
      Rails.application.routes.url_helpers.api_v1_root_url(
        host: Rails.application.config.action_mailer.default_url_options[:host],
        protocol: 'https'
      )
    end
    
    def supabase_url
      # Use team's custom Supabase if configured, otherwise use default
      if @app.team_database_config&.custom_supabase?
        @app.team_database_config.supabase_url
      else
        ENV['SUPABASE_URL']
      end
    end
    
    def supabase_anon_key
      # Use team's custom Supabase if configured, otherwise use default
      if @app.team_database_config&.custom_supabase?
        @app.team_database_config.supabase_anon_key
      else
        ENV['SUPABASE_ANON_KEY']
      end
    end
    
    def decrypt_value(setting)
      # In production, this would properly decrypt the value
      # For now, return a placeholder for security
      Rails.env.production? ? '[ENCRYPTED]' : setting.value
    end
  end
end