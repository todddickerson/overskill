module Ai
  # Service to build base context with essential template files
  # Prevents Claude from constantly re-reading core files via os-view
  class BaseContextService
    TEMPLATE_PATH = Rails.root.join("app/services/ai/templates/overskill_20250728")
    
    # Files that are ALWAYS accessed during app generation
    ESSENTIAL_FILES = [
      "src/index.css",           # Design system - modified 21 times in analysis
      "tailwind.config.ts",      # Tailwind config - constantly referenced
      "index.html",              # Base HTML structure
      "src/App.tsx",             # Main app component with routing
      "src/pages/Index.tsx",     # Default page structure  
      "src/main.tsx",            # App entry point
      "src/lib/utils.ts",        # Utility functions
      "package.json"             # Dependencies and scripts
    ].freeze
    
    # Component files that are commonly needed
    COMMON_UI_COMPONENTS = [
      "src/components/ui/button.tsx",
      "src/components/ui/card.tsx", 
      "src/components/ui/input.tsx",
      "src/components/ui/label.tsx",
      "src/components/ui/toast.tsx",
      "src/components/ui/toaster.tsx"
    ].freeze
    
    def initialize(app = nil)
      @app = app
    end
    
    # Build useful-context section with base template files
    def build_useful_context
      context = []
      
      context << "# useful-context"
      context << ""
      context << "Below are the essential base template files for this React + TypeScript + Tailwind project."
      context << "These files are already available - DO NOT use os-view to read them again."
      context << "Use os-line-replace to modify them or reference their structure."
      context << ""
      
      # Add essential files first
      ESSENTIAL_FILES.each do |file_path|
        add_file_to_context(context, file_path, "Essential")
      end
      
      # Add common UI components
      context << "## Common UI Components (shadcn/ui)"
      context << ""
      COMMON_UI_COMPONENTS.each do |file_path|
        add_file_to_context(context, file_path, "UI Component")
      end
      
      # Add app-specific context if app exists
      if @app
        add_app_specific_context(context)
      end
      
      context.join("\n")
    end
    
    # Build context for existing app files (to prevent re-reading)
    def build_existing_files_context(app)
      return "" unless app&.app_files&.any?
      
      context = []
      context << ""
      context << "## Existing App Files"
      context << ""
      context << "The following files already exist in this app - reference them directly:"
      context << ""
      
      # Group files by directory for better organization
      files_by_dir = app.app_files.order(:path).group_by { |f| File.dirname(f.path) }
      
      files_by_dir.each do |dir, files|
        context << "### #{dir == '.' ? 'Root' : dir}/"
        files.each do |file|
          context << ""
          context << "**#{file.path}** (#{file.file_type})"
          context << "```#{get_file_extension(file.path)}"
          context << file.content.to_s.strip
          context << "```"
          context << ""
        end
      end
      
      context.join("\n")
    end
    
    private
    
    def add_file_to_context(context, file_path, category)
      full_path = TEMPLATE_PATH.join(file_path)
      
      if File.exist?(full_path)
        content = File.read(full_path)
        context << "## #{category}: #{file_path}"
        context << ""
        context << "```#{get_file_extension(file_path)}"
        context << content.strip
        context << "```"
        context << ""
      else
        Rails.logger.warn "[BaseContext] Template file not found: #{file_path}"
      end
    end
    
    def add_app_specific_context(context)
      return unless @app
      
      context << ""
      context << "## App-Specific Information"
      context << ""
      context << "**App Name**: #{@app.name}"
      context << "**Description**: #{@app.description}" if @app.description.present?
      context << "**User Request**: #{@app.prompt}" if @app.prompt.present?
      
      # Add existing files if any
      if @app.app_files.any?
        context << ""
        context << "**Existing Files**: #{@app.app_files.count} files already created"
        context << "Most recent files:"
        @app.app_files.order(updated_at: :desc).limit(5).each do |file|
          context << "- #{file.path} (#{file.file_type})"
        end
      end
      
      context << ""
    end
    
    def get_file_extension(file_path)
      case File.extname(file_path).downcase
      when '.tsx', '.ts'
        'typescript'
      when '.jsx', '.js'  
        'javascript'
      when '.css'
        'css'
      when '.html'
        'html'
      when '.json'
        'json'
      else
        'text'
      end
    end
  end
end