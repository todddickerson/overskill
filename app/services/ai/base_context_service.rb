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
      "package.json"       # Dependencies - shows available libraries
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
      'todo' => %w[input checkbox button card],
      'landing' => %w[button card badge tabs],
      'dashboard' => %w[table select dropdown-menu avatar],
      'form' => %w[form input textarea select button],
      'default' => %w[button card input]  # Minimal fallback
    }.freeze
    
    def initialize(app = nil)
      @app = app
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
      
      # COST OPTIMIZATION: UI components loaded selectively via ComponentRequirementsAnalyzer
      context << "## Available UI Components (shadcn/ui)"
      context << ""
      context << "The following components are available in the template and can be imported as needed:"
      context << ""
      
      # List available components without loading their full content
      all_components = %w[
        button card input textarea select checkbox radio-group form label
        table dialog dropdown-menu tabs alert toast toaster badge skeleton switch
        avatar accordion alert-dialog aspect-ratio breadcrumb calendar
        carousel chart collapsible command context-menu data-table
        date-picker drawer hover-card menubar navigation-menu
        pagination popover progress radio-group resizable
        scroll-area separator sheet sidebar slider sonner
        toggle toggle-group tooltip
      ]
      
      context << "**Available Components**: #{all_components.join(', ')}"
      context << ""
      context << "**Usage**: Import these directly without using os-view to read component files."
      context << "**Example**: `import { Button } from '@/components/ui/button'`"
      context << ""
      
      # Add app-specific context if app exists
      if @app
        add_app_specific_context(context)
      end
      
      final_context = context.join("\n")
      
      # COST MONITORING: Log context size for optimization tracking
      context_size = final_context.length
      Rails.logger.info "[V5_COST] Context size: #{context_size} chars (target: <50k for optimization)"
      
      if context_size > 100_000
        Rails.logger.error "[V5_COST] CONTEXT BLOAT: #{context_size} chars - urgent optimization needed"
      elsif context_size > 50_000
        Rails.logger.warn "[V5_COST] Context size warning: #{context_size} chars - consider further optimization"
      else
        Rails.logger.info "[V5_COST] Context optimized: #{context_size} chars - good!"
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