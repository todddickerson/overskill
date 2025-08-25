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
    
    # REMOVED: Replaced with AI-powered component prediction in ComponentRequirementsAnalyzer
    # The analyzer now uses sophisticated intent analysis instead of fixed mappings
    # This handles edge cases like 'admin app', 'SAAS app', 'graphing app' much better
    
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
      elsif @load_components && @app_type != 'general'
        # Show predicted components for this app type
        context << "## Predicted Components for #{@app_type.capitalize} App Type"
        context << "Based on AI analysis, these components are likely to be useful:"
        context << @component_requirements.take(MAX_COMPONENTS_TO_LOAD).map { |c| "`#{c}`" }.join(', ')
        context << ""
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
    
    # Build optimized context with only relevant files (REPLACES build_existing_files_context)
    # This consolidates the duplicate logic and includes only essential + predicted files
    def build_complete_context(app, options = {})
      return build_useful_context unless app&.app_files&.any?
      
      component_requirements = options[:component_requirements] || []
      app_type = options[:app_type] || detect_app_type
      
      context = []
      context << "# useful-context"
      context << ""
      context << "Below are the ONLY relevant files for this request in this React + TypeScript + Tailwind app."
      context << "These files exist in the app - use os-line-replace to modify them."
      context << "DO NOT use os-view to read them again as they are shown below."
      context << ""
      
      # Get only the files that are actually relevant
      relevant_files = get_relevant_files(app, component_requirements, app_type)
      
      Rails.logger.info "[OPTIMIZATION] Including #{relevant_files.count} relevant files (was #{app.app_files.count})"
      
      # Group relevant files by category for better organization
      essential_files = relevant_files.select { |f| ESSENTIAL_FILES.include?(f.path) }
      component_files = relevant_files.select { |f| f.path.include?('components/ui/') }
      other_files = relevant_files - essential_files - component_files
      
      # Add essential files first
      if essential_files.any?
        context << "## Essential App Files"
        essential_files.each do |file|
          add_app_file_to_context(context, file, "Essential")
        end
      end
      
      # Add predicted components
      if component_files.any?
        context << "## Predicted UI Components for This Request"
        context << "Based on analysis, these components are likely needed:"
        component_files.each do |file|
          add_app_file_to_context(context, file, "Component")
        end
      end
      
      # Add other relevant files
      if other_files.any?
        context << "## Other Relevant Files"
        other_files.each do |file|
          add_app_file_to_context(context, file, "Modified")
        end
      end
      
      # Add available components reference (without loading them all)
      add_available_components_reference(context)
      
      # Add app-specific context
      add_app_specific_context(context)
      
      final_context = context.join("\n")
      
      # Log optimization results
      context_size = final_context.length
      token_estimate = context_size / 4
      
      Rails.logger.info "[OPTIMIZATION] Complete context: #{context_size} chars (~#{token_estimate} tokens)"
      Rails.logger.info "[OPTIMIZATION] Files included: #{relevant_files.count}/#{app.app_files.count}"
      Rails.logger.info "[OPTIMIZATION] Reduction: #{((1 - relevant_files.count.to_f / app.app_files.count) * 100).round}%"
      
      if token_estimate < 30_000
        Rails.logger.info "[OPTIMIZATION] ✅ Target achieved: <30k tokens"
      else
        Rails.logger.warn "[OPTIMIZATION] ⚠️ Still above target: #{token_estimate} tokens"
      end
      
      final_context
    end
    
    # DEPRECATED: Use build_complete_context instead
    # Keeping for backward compatibility during transition
    def build_existing_files_context(app)
      Rails.logger.warn "[DEPRECATED] build_existing_files_context called - use build_complete_context instead"
      # Return empty string to break the 71k token inclusion
      # This forces callers to use the optimized method
      ""
    end
    
    private
    
    # Get only files that are relevant for the current request, including indirect dependencies
    def get_relevant_files(app, component_requirements, app_type)
      relevant_files = []
      processed_files = Set.new
      
      # 1. ALWAYS include essential files that exist
      essential_files = ESSENTIAL_FILES.map { |path| 
        app.app_files.find_by(path: path) 
      }.compact
      relevant_files += essential_files
      essential_files.each { |f| processed_files << f.path }
      
      # 2. Include predicted components and their dependencies
      component_requirements.take(MAX_COMPONENTS_TO_LOAD).each do |component_name|
        component_file = app.app_files.find_by(path: "src/components/ui/#{component_name}.tsx")
        if component_file && !processed_files.include?(component_file.path)
          relevant_files << component_file
          processed_files << component_file.path
          
          # Recursively include dependencies
          deps = find_indirect_dependencies(app, component_file, processed_files)
          relevant_files += deps
          deps.each { |d| processed_files << d.path }
        end
      end
      
      # 3. Include recently modified files (indication of active work)
      recently_modified = app.app_files.where('updated_at > ?', 1.hour.ago)
                                       .where.not(path: processed_files.to_a)
                                       .limit(3)
      relevant_files += recently_modified
      
      # 4. Ensure we don't exceed reasonable limits
      unique_files = relevant_files.compact.uniq
      if unique_files.count > 25  # Increased limit to account for dependencies
        Rails.logger.warn "[FILE_SELECTION] Too many files (#{unique_files.count}), prioritizing..."
        # Prioritize: essential files > components > dependencies > recently modified
        unique_files = essential_files + 
                      relevant_files.select { |f| f.path.include?('components/ui/') }.take(8) +
                      recently_modified.take(3)
      end
      
      Rails.logger.info "[FILE_SELECTION] Essential: #{essential_files.count}, Components: #{component_requirements.count}, Dependencies: #{processed_files.size - essential_files.count - component_requirements.count}, Recent: #{recently_modified.count}"
      
      unique_files.compact.uniq
    end
    
    # Find indirect dependencies (helper files, shared components, etc.)
    def find_indirect_dependencies(app, file, processed_files, max_depth = 2, current_depth = 0)
      return [] if current_depth >= max_depth || !file.content
      
      dependencies = []
      
      # Parse import statements
      imports = file.content.scan(/import\s+(?:\{[^}]+\}|\*\s+as\s+\w+|\w+)\s+from\s+['"]([^'"]+)['"]/).flatten
      
      imports.each do |import_path|
        # Skip external dependencies
        next if import_path.start_with?('node_modules') || !import_path.match?(/^\.\.?\/|^@\/|^~\//)
        
        # Resolve the import path
        resolved_path = resolve_import_path(file.path, import_path)
        
        # Skip if already processed
        next if processed_files.include?(resolved_path)
        
        # Find the dependency file
        dep_file = app.app_files.find_by(path: resolved_path)
        if dep_file
          dependencies << dep_file
          processed_files << resolved_path
          
          # Recursively find nested dependencies
          nested_deps = find_indirect_dependencies(app, dep_file, processed_files, max_depth, current_depth + 1)
          dependencies += nested_deps
        else
          Rails.logger.debug "[DEPENDENCY] Missing indirect dependency: #{resolved_path} (imported by #{file.path})"
        end
      end
      
      dependencies
    end
    
    # Resolve import paths (handles relative paths and aliases)
    def resolve_import_path(current_file, import_path)
      if import_path.start_with?('./')
        dir = File.dirname(current_file)
        normalized = File.join(dir, import_path.sub('./', ''))
        # Add extension if missing
        add_typescript_extension(normalized)
      elsif import_path.start_with?('../')
        dir = File.dirname(current_file)
        normalized = File.expand_path(File.join(dir, import_path))
        add_typescript_extension(normalized)
      elsif import_path.start_with?('@/')
        # @ alias for src/
        normalized = import_path.sub('@/', 'src/')
        add_typescript_extension(normalized)
      elsif import_path.start_with?('~/')
        # ~ alias for lib/
        normalized = import_path.sub('~/', 'src/lib/')
        add_typescript_extension(normalized)
      else
        import_path
      end
    end
    
    # Add TypeScript extension if missing
    def add_typescript_extension(path)
      return path if path.match?(/\.(tsx?|jsx?|css|json)$/)
      
      # Try common extensions in order
      %w[.tsx .ts .jsx .js].each do |ext|
        test_path = "#{path}#{ext}"
        return test_path if File.basename(test_path).start_with?('.')
      end
      
      # Default to .tsx for components, .ts for others
      path.include?('components') ? "#{path}.tsx" : "#{path}.ts"
    end
    
    # Add reference to available components without loading them all
    def add_available_components_reference(context)
      context << ""
      context << "## Available UI Components (shadcn/ui) - NOT Pre-loaded"
      context << ""
      context << "These components exist and can be imported as needed:"
      context << ""
      context << "**Form**: button, input, textarea, select, checkbox, radio-group, form, label"
      context << "**Layout**: card, table, dialog, tabs, separator, scroll-area, sheet"
      context << "**Navigation**: dropdown-menu, menubar, navigation-menu, breadcrumb"
      context << "**Feedback**: alert, toast, badge, skeleton, progress, sonner"
      context << "**Data**: avatar, accordion, collapsible, popover, tooltip, hover-card"
      context << "**Advanced**: command, calendar, date-picker, carousel, chart, sidebar"
      context << ""
      context << "**Usage**: Import directly: `import { Button } from '@/components/ui/button'`"
      context << "**Note**: Use os-view to read component files if needed for customization"
      context << ""
    end
    
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