module Ai
  # Service for managing static template context that rarely changes
  # Optimized for Anthropic's 1-hour caching (cache_control: ephemeral)
  class TemplateContextService
    include TemplateConfig
    
    # Template essentials - reduced to absolute minimum for AI understanding
    # These are the files AI needs to understand the project structure
    TEMPLATE_ESSENTIALS = [
      "package.json",          # Dependencies and scripts
      "tailwind.config.ts",    # Design system configuration
      "vite.config.ts",        # Build configuration
      "src/App.tsx",          # Routing and app structure
      "src/main.tsx",         # Application entry point
      "src/lib/supabase.ts"   # Database client exports (critical for imports)
    ].freeze
    
    # Optional template files - included if they exist and budget allows
    TEMPLATE_OPTIONAL = [
      "src/index.css",        # Global styles (can be large)
      "index.html",           # HTML template
      "tsconfig.json"         # TypeScript configuration
    ].freeze
    
    # UI Components available in the template
    # These are pre-installed shadcn/ui components ready to use
    UI_COMPONENTS_MANIFEST = {
      "Forms" => ["button", "input", "textarea", "select", "checkbox", "radio-group", "switch", "slider", "date-picker", "form", "label"],
      "Layout" => ["card", "separator", "aspect-ratio", "scroll-area", "resizable"],
      "Navigation" => ["navigation-menu", "breadcrumb", "dropdown-menu", "menubar", "context-menu", "command", "tabs"],
      "Data Display" => ["table", "badge", "avatar", "calendar", "chart", "carousel", "accordion", "collapsible"],
      "Feedback" => ["alert", "alert-dialog", "dialog", "drawer", "popover", "tooltip", "toast", "progress", "skeleton", "sonner"],
      "Typography" => ["heading", "text", "code", "blockquote"],
      "Overlays" => ["sheet", "hover-card"]
    }.freeze
    
    def initialize(template_base = nil)
      @template_base = template_base || default_template_base
      @token_counter = TokenCountingService.new
    end
    
    # Build template context optimized for 1-hour caching
    # This context rarely changes and can be cached aggressively
    def build_template_context(budget_manager)
      context = []
      
      Rails.logger.info "[TemplateContext] Building template context for Anthropic 1-hour cache"
      
      # Add system-level context first
      system_header = build_system_header()
      if budget_manager.can_add_content?(:system_context, system_header)
        budget_manager.add_content(:system_context, system_header, "System header")
        context << system_header
      end
      
      # Load essential template files
      essential_files = load_template_files(TEMPLATE_ESSENTIALS)
      selected_essentials = budget_manager.select_files_within_budget(
        essential_files, 
        :template_context,
        calculate_template_relevance_scores(essential_files)
      )
      
      if selected_essentials.any?
        context << "## Template Structure (Cached 1h)"
        context << "Core project files that define the application architecture:"
        context << ""
        
        selected_essentials.each do |file|
          add_template_file_to_context(context, file)
        end
      end
      
      # Add optional template files if budget allows
      optional_files = load_template_files(TEMPLATE_OPTIONAL)
      selected_optional = budget_manager.select_files_within_budget(
        optional_files,
        :template_context,
        calculate_template_relevance_scores(optional_files)
      )
      
      if selected_optional.any?
        context << "## Additional Template Files"
        selected_optional.each do |file|
          add_template_file_to_context(context, file)
        end
      end
      
      # Add template usage instructions
      usage_instructions = build_usage_instructions()
      if budget_manager.can_add_content?(:system_context, usage_instructions)
        budget_manager.add_content(:system_context, usage_instructions, "Usage instructions")
        context << usage_instructions
      end
      
      final_content = context.join("\n")
      tokens_used = @token_counter.count_tokens(final_content)
      
      Rails.logger.info "[TemplateContext] Built template context: #{tokens_used} tokens (#{selected_essentials.count + selected_optional.count} files)"
      Rails.logger.info "[TemplateContext] Optimized for Anthropic 1-hour caching"
      
      final_content
    end
    
    # Get cache key for template context (for external caching)
    def template_cache_key(template_version = nil)
      version = template_version || @template_base
      "template_context:#{version}:#{template_files_hash}"
    end
    
    # Check if template has changed (for cache invalidation)
    def template_changed_since?(timestamp)
      # Check if any template files have been modified
      TEMPLATE_ESSENTIALS.any? do |file_path|
        template_file = load_template_file(file_path)
        template_file && template_file.updated_at > timestamp
      end
    end
    
    private
    
    def build_system_header
      lines = []
      lines << "# OverSkill Platform - AI-Powered App Generation"
      lines << ""
      lines << "## Template Context (1-hour cached)"
      lines << "This context contains the base template structure for generating new applications."
      lines << "Template files are cached for 1 hour as they change infrequently."
      lines << ""
      lines << "**Stack**: React + TypeScript + Vite + Tailwind CSS + shadcn/ui"
      lines << "**Architecture**: Single-page application with modern React patterns"
      lines << ""
      
      lines.join("\n")
    end
    
    def build_usage_instructions
      lines = []
      lines << ""
      lines << "## Template Usage Guidelines"
      lines << ""
      lines << "**File Structure**:"
      lines << "- All source files go in `src/` directory"
      lines << "- Components use `.tsx` extension for React components"
      lines << "- Utilities and logic use `.ts` extension"
      lines << "- Styles are managed through Tailwind classes"
      lines << ""
      lines << "**Import Conventions**:"
      lines << "- Use `@/` alias for `src/` directory"
      lines << "- Import UI components from `@/components/ui/`"
      lines << "- Import utilities from `@/lib/`"
      lines << ""
      lines << "**Available UI Components (Pre-installed shadcn/ui):**"
      lines << ""
      UI_COMPONENTS_MANIFEST.each do |category, components|
        lines << "• **#{category}**: #{components.join(', ')}"
      end
      lines << ""
      lines << "All components are TypeScript-ready and styled with Tailwind CSS."
      lines << "Import example: `import { Button } from '@/components/ui/button'`"
      lines << ""
      lines << "**Component Patterns**:"
      lines << "- Use functional components with TypeScript"
      lines << "- Follow React hooks patterns for state management"
      lines << "- Use shadcn/ui components for consistent design"
      lines << ""
      
      lines.join("\n")
    end
    
    def load_template_files(file_paths)
      files = []
      
      file_paths.each do |file_path|
        template_file = load_template_file(file_path)
        files << template_file if template_file
      end
      
      files
    end
    
    def load_template_file(file_path)
      # This would load from the template system
      # For now, return a mock object that matches AppFile interface
      return nil unless File.exist?(File.join(@template_base, file_path))
      
      content = File.read(File.join(@template_base, file_path))
      OpenStruct.new(
        path: file_path,
        content: content,
        updated_at: File.mtime(File.join(@template_base, file_path))
      )
    rescue => e
      Rails.logger.warn "[TemplateContext] Could not load template file #{file_path}: #{e.message}"
      nil
    end
    
    def add_template_file_to_context(context, file)
      context << "### #{file.path}"
      context << ""
      context << "```#{get_file_extension(file.path)}"
      
      # Add line numbers for consistency with app files
      numbered_content = file.content.lines.map.with_index(1) do |line, num|
        "#{num.to_s.rjust(4)}: #{line}"
      end.join
      
      context << numbered_content.rstrip
      context << "```"
      context << ""
    end
    
    def get_file_extension(file_path)
      ext = ::File.extname(file_path).downcase
      case ext
      when '.tsx', '.ts'
        'typescript'
      when '.jsx', '.js'
        'javascript'
      when '.json'
        'json'
      when '.css'
        'css'
      when '.html'
        'html'
      else
        'text'
      end
    end
    
    def calculate_template_relevance_scores(files)
      scores = {}
      
      files.each do |file|
        score = 1.0
        
        # Higher priority for essential structure files
        if file.path == 'package.json'
          score = 3.0  # Critical for understanding dependencies
        elsif file.path == 'src/App.tsx'
          score = 2.5  # Important for routing structure
        elsif file.path == 'tailwind.config.ts'
          score = 2.0  # Important for styling
        elsif file.path.include?('config')
          score = 1.5  # Configuration files are moderately important
        end
        
        # Lower priority for potentially large files
        if file.path == 'src/index.css'
          score *= 0.7  # CSS can be large and less essential
        end
        
        scores[file.path] = score
      end
      
      scores
    end
    
    def template_files_hash
      # Create a hash of all template file contents for cache invalidation
      content = TEMPLATE_ESSENTIALS.map do |file_path|
        template_file = load_template_file(file_path)
        template_file&.content || ""
      end.join
      
      Digest::SHA256.hexdigest(content)[0..8]  # Short hash for cache key
    end
    
    def default_template_base
      Rails.root.join('app', 'services', 'ai', 'templates', 'overskill_20250728')
    end
  end
end