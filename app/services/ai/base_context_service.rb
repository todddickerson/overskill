module Ai
  # Service to build base context with essential app files
  # Shows the actual files that exist in the app (copied from template)
  class BaseContextService
    include TemplateConfig
    
    # OPTIMIZED: Core essential files only (80% cost reduction)
    # Based on V5 cost analysis - reduced from 11 files to 5 core files
    ESSENTIAL_FILES = [
      "src/index.css",     # Design system - contains all Tailwind styles
      "src/App.tsx",       # Routing structure - shows app architecture
      "src/main.tsx",      # React entry point - shows how app initializes
      "index.html",        # HTML template - shows app structure
      "package.json",      # Dependencies - shows available libraries
      "tailwind.config.ts", # Tailwind configuration
      "vite.config.ts"     # Vite configuration
    ].freeze
    
    # ARCHIVED: Previously loaded files (moved to selective loading)
    # These are now loaded only when ComponentRequirementsAnalyzer determines need:
    # - "tailwind.config.ts", "src/pages/Index.tsx", "src/lib/utils.ts"
    # - "vite.config.ts", "src/lib/supabase.ts", "src/hooks/use-toast.ts"
    
    # OPTIMIZED: Selective component loading (replaces blanket loading)
    # DISABLED for cost optimization - components loaded on-demand via ComponentRequirementsAnalyzer
    # This reduces context from 300k+ to ~30k characters (90% cost reduction)
    
    # ARCHIVED: Common UI components (now loaded selectively)
    # Previously loaded ALL 20+ components in every API call regardless of need
    # COMMON_UI_COMPONENTS = [
    #   # Form components: form.tsx, input.tsx, textarea.tsx, select.tsx, checkbox.tsx, radio-group.tsx
    #   # Display components: button.tsx, card.tsx, table.tsx, dialog.tsx, label.tsx  
    #   # Navigation: dropdown-menu.tsx, tabs.tsx, alert.tsx, toast.tsx, toaster.tsx
    #   # Status: badge.tsx, skeleton.tsx, switch.tsx
    # ].freeze
    
    # NEW: App-type specific component mapping (load only what's needed)
    APP_TYPE_COMPONENTS = {
      'todo' => %w[input checkbox button card label],
      'landing' => %w[button card badge tabs],
      'dashboard' => %w[table select dropdown-menu avatar card],
      'form' => %w[form input textarea select button label],
      'ecommerce' => %w[card button badge input select],
      'blog' => %w[card button badge separator],
      'chat' => %w[input button card avatar scroll-area],
      'default' => %w[button card input]  # Minimal fallback
    }.freeze
    
    # Maximum components to load per request (token optimization)
    MAX_COMPONENTS_TO_LOAD = 5
    
    def initialize(app = nil, options = {})
      @app = app
      @app_type = options[:app_type] || detect_app_type
      @load_components = options[:load_components] != false  # Default true
      @component_requirements = options[:component_requirements] || []
    end
    
    # Build useful-context section with base template files
    def build_useful_context
      context = []
      
      context << "# useful-context"
      context << ""
      context << "Below are the essential files in this React + TypeScript + Tailwind app."
      context << "These files already exist in the app - use os-line-replace to modify them."
      context << "DO NOT use os-view to read them again as they are shown below."
      context << ""
      
      # Only show files that actually exist in the app
      # Template files were already copied when the app was created
      if @app
        ESSENTIAL_FILES.each do |file_path|
          if (app_file = @app.app_files.find_by(path: file_path))
            add_app_file_to_context(context, app_file, "Essential")
          end
        end
      else
        context << "NOTE: No app context available yet."
      end
      
      # COST OPTIMIZATION: Only list components, don't load them
      context << "## Available UI Components (shadcn/ui)"
      context << ""
      context << "The following UI components exist in the template and can be imported:"
      context << ""
      
      # Component categories for reference only
      context << "**Form Components**: button, input, textarea, select, checkbox, radio-group, form, label"
      context << "**Layout Components**: card, table, dialog, tabs, separator, scroll-area"
      context << "**Navigation**: dropdown-menu, menubar, navigation-menu, breadcrumb"
      context << "**Feedback**: alert, toast, badge, skeleton, progress"
      context << "**Data Display**: avatar, accordion, collapsible, popover, tooltip"
      context << "**Advanced**: command, data-table, calendar, date-picker, carousel"
      context << ""
      context << "**IMPORTANT**: DO NOT use os-view to read these component files."
      context << "**Usage**: Import directly: `import { Button } from '@/components/ui/button'`"
      context << ""
      
      # Selectively load only needed components if specified
      if @load_components && @component_requirements.any?
        context << "## Pre-loaded Components for This Request"
        context << "Based on the user's request, these components are loaded:"
        context << ""
        
        components_to_load = @component_requirements.take(MAX_COMPONENTS_TO_LOAD)
        components_to_load.each do |component_name|
          add_component_to_context(context, component_name)
        end
      elsif @load_components && @app_type != 'default'
        # Load app-type specific components
        components = APP_TYPE_COMPONENTS[@app_type] || APP_TYPE_COMPONENTS['default']
        if components.any?
          context << "## Common Components for #{@app_type.capitalize} Apps"
          context << "Import these components as needed (not pre-loaded to save tokens):"
          context << components.map { |c| "`#{c}`" }.join(', ')
          context << ""
        end
      end
      context << ""
      
      # Add app-specific context if app exists
      if @app
        add_app_specific_context(context)
      end
      
      final_context = context.join("\n")
      
      # COST MONITORING: Log context size for optimization tracking
      context_size = final_context.length
      token_estimate = context_size / 4  # Rough estimate: 4 chars per token
      
      Rails.logger.info "[CACHE_OPTIMIZATION] Context size: #{context_size} chars (~#{token_estimate} tokens)"
      Rails.logger.info "[CACHE_OPTIMIZATION] Target: <30k chars (<7.5k tokens)"
      Rails.logger.info "[CACHE_OPTIMIZATION] Components loaded: #{@component_requirements.size} of #{MAX_COMPONENTS_TO_LOAD} max"
      
      if context_size > 50_000
        Rails.logger.error "[CACHE_OPTIMIZATION] ⚠️ CONTEXT BLOAT: #{context_size} chars - optimization failed!"
      elsif context_size > 30_000
        Rails.logger.warn "[CACHE_OPTIMIZATION] ⚠️ Context above target: #{context_size} chars"
      else
        Rails.logger.info "[CACHE_OPTIMIZATION] ✅ Context optimized: #{context_size} chars"
      end
      
      final_context
    end
    
    # Build context for existing app files (to prevent re-reading)
    def build_existing_files_context(app)
      return "" unless app&.app_files&.any?
      
      context = []
      context << ""
      context << "## Existing App Files (ACTUALLY IN THE APP)"
      context << ""
      context << "The following files ACTUALLY EXIST in this app and can be modified with os-line-replace:"
      context << "IMPORTANT: Only these files can be modified with os-line-replace. Template files shown above are for reference only."
      context << ""
      
      # Group files by directory for better organization
      files_by_dir = app.app_files.order(:path).group_by { |f| ::File.dirname(f.path) }
      
      files_by_dir.each do |dir, files|
        context << "### #{dir == '.' ? 'Root' : dir}/"
        files.each do |file|
          context << ""
          context << "**#{file.path}** (#{file.file_type})"
          context << "```#{get_file_extension(file.path)}"
          # Add line numbers for consistent display with os-view/os-read
          numbered_content = file.content.to_s.lines.map.with_index(1) do |line, num|
            "#{num.to_s.rjust(4)}: #{line}"
          end.join
          context << numbered_content.rstrip
          context << "```"
          context << ""
        end
      end
      
      context.join("\n")
    end
    
    private
    
    def detect_app_type
      return 'default' unless @app
      
      # Handle both App objects and Hash objects
      if @app.is_a?(App)
        text = "#{@app.name} #{@app.description} #{@app.prompt}".downcase
      elsif @app.is_a?(Hash)
        # When @app is a hash (e.g., from context_data)
        text = "#{@app[:name]} #{@app[:description]} #{@app[:prompt]}".downcase
      else
        return 'default'
      end
      
      return 'todo' if text.match?(/todo|task|checklist/)
      return 'landing' if text.match?(/landing|marketing|hero|startup/)
      return 'dashboard' if text.match?(/dashboard|analytics|admin|metrics/)
      return 'form' if text.match?(/form|survey|registration|application/)
      return 'ecommerce' if text.match?(/shop|store|product|cart|ecommerce/)
      return 'blog' if text.match?(/blog|article|post|content/)
      return 'chat' if text.match?(/chat|message|conversation/)
      
      'default'
    end
    
    def add_component_to_context(context, component_name)
      # Only load the component if it exists in the app files
      component_path = "src/components/ui/#{component_name}.tsx"
      
      if @app && (component_file = @app.app_files.find_by(path: component_path))
        context << "### Component: #{component_name}"
        context << "```typescript"
        context << component_file.content
        context << "```"
        context << ""
      else
        # Component not yet copied to app - just reference it
        context << "• **#{component_name}**: Available at `@/components/ui/#{component_name}`"
      end
    end
    
    def add_app_file_to_context(context, app_file, category)
      context << "## #{category}: #{app_file.path}"
      context << ""
      context << "```#{get_file_extension(app_file.path)}"
      # Add line numbers for consistent display with os-view/os-read
      numbered_content = app_file.content.to_s.lines.map.with_index(1) do |line, num|
        "#{num.to_s.rjust(4)}: #{line}"
      end.join
      context << numbered_content.rstrip
      context << "```"
      context << ""
    end
    
    # This method is now deprecated since we only show actual app files
    # Keeping it for backwards compatibility but it shouldn't be used
    def add_file_to_context(context, file_path, category)
      Rails.logger.warn "[BaseContext] Deprecated: add_file_to_context called for #{file_path}"
      # No longer reading from template directory
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
      case ::File.extname(file_path).downcase
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