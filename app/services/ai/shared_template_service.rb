module Ai
  class SharedTemplateService
    def initialize(app)
      @app = app
    end
    
    def generate_core_files
      Rails.logger.info "[SharedTemplateService] Generating core foundation files for app ##{@app.id}"
      
      CORE_TEMPLATES.each do |category, files|
        Rails.logger.info "[SharedTemplateService] Generating #{category} templates: #{files.join(', ')}"
        files.each { |file| create_file_from_template(category, file) }
      end
      
      Rails.logger.info "[SharedTemplateService] Generated #{total_files_count} core foundation files"
    end
    
    private
    
    CORE_TEMPLATES = {
      auth: ['login.tsx', 'signup.tsx', 'protected-route.tsx', 'forgot-password.tsx'],
      database: ['supabase-client.ts', 'app-scoped-db.ts', 'rls-helpers.ts'],
      routing: ['app-router.tsx', 'route-config.ts', 'navigation.tsx'],
      core: ['package.json', 'vite.config.ts', 'index.html', 'tsconfig.json', 'tailwind.config.js', 'lib-utils.ts']
    }.freeze
    
    def create_file_from_template(category, filename)
      template_path = Rails.root.join('app', 'templates', 'shared', category.to_s, filename)
      
      unless File.exist?(template_path)
        Rails.logger.warn "[SharedTemplateService] Template not found: #{template_path}"
        return false
      end
      
      # Read template content
      template_content = File.read(template_path)
      
      # Process template variables (e.g., {{APP_ID}}, {{APP_NAME}})
      processed_content = process_template_variables(template_content)
      
      # Determine target path in app structure
      target_path = determine_target_path(category, filename)
      
      # Create app file
      app_file = @app.app_files.create!(
        path: target_path,
        content: processed_content,
        team: @app.team
      )
      
      Rails.logger.debug "[SharedTemplateService] Created #{target_path} from template"
      app_file
    end
    
    def process_template_variables(content)
      # Replace template variables with app-specific values
      content
        .gsub('{{APP_ID}}', @app.id.to_s)
        .gsub('{{APP_NAME}}', @app.name)
        .gsub('{{APP_SLUG}}', @app.slug)
        .gsub('{{SUPABASE_URL}}', supabase_url)
        .gsub('{{SUPABASE_ANON_KEY}}', supabase_anon_key)
    end
    
    def determine_target_path(category, filename)
      case category.to_sym
      when :auth
        "src/pages/auth/#{filename}"
      when :database
        "src/lib/#{filename}"
      when :routing
        "src/components/routing/#{filename}"
      when :core
        if filename == 'lib-utils.ts'
          "src/lib/utils.ts"  # shadcn/ui standard location
        else
          filename # Root level files
        end
      else
        "src/#{filename}"
      end
    end
    
    def supabase_url
      # Get from app environment variables or default
      @app.app_env_vars.find_by(key: 'SUPABASE_URL')&.value || 
        ENV['SUPABASE_URL'] || 
        'https://your-project.supabase.co'
    end
    
    def supabase_anon_key
      # Get from app environment variables or default  
      @app.app_env_vars.find_by(key: 'SUPABASE_ANON_KEY')&.value ||
        ENV['SUPABASE_ANON_KEY'] ||
        'your-anon-key'
    end
    
    def total_files_count
      CORE_TEMPLATES.values.flatten.size
    end
  end
end