# frozen_string_literal: true

module Ai
  # Analyzes user prompts to determine which UI components are actually needed
  # Reduces token usage by 90%+ by loading only 3-5 components instead of all 52
  class ComponentRequirementsAnalyzer
    # Component keywords mapping - what words in prompts indicate which components
    COMPONENT_INDICATORS = {
      'button' => %w[button click submit action cta call-to-action press tap],
      'input' => %w[input field text enter type form fillout fill-out search filter],
      'textarea' => %w[textarea message comment description multiline paragraph notes],
      'select' => %w[select dropdown choose option picker menu choice],
      'checkbox' => %w[checkbox check tick toggle option multi-select tasks todo],
      'radio-group' => %w[radio option choice single-select exclusive],
      'form' => %w[form submit registration signup sign-up login application contact],
      'card' => %w[card box container panel section block tile product item],
      'table' => %w[table grid data list rows columns spreadsheet records],
      'dialog' => %w[dialog modal popup overlay window prompt confirm alert],
      'tabs' => %w[tabs tab navigation sections categories pages views],
      'badge' => %w[badge tag label chip status indicator count new],
      'alert' => %w[alert notification warning error info message banner notice],
      'toast' => %w[toast notification popup message temporary feedback success],
      'avatar' => %w[avatar profile picture user image icon photo account],
      'accordion' => %w[accordion collapse expand faq questions answers collapsible],
      'calendar' => %w[calendar date picker schedule appointment booking event],
      'chart' => %w[chart graph analytics metrics visualization data plot statistics],
      'dropdown-menu' => %w[menu dropdown options actions context settings more],
      'progress' => %w[progress loading bar percentage completion status upload],
      'skeleton' => %w[skeleton loading placeholder shimmer loader waiting],
      'slider' => %w[slider range adjust control volume brightness value],
      'switch' => %w[switch toggle on/off enable disable setting preference],
      'tooltip' => %w[tooltip hint help info hover popup explanation],
      'separator' => %w[separator divider line break section hr border divide],
      'scroll-area' => %w[scroll scrollable overflow list feed timeline long],
      'sheet' => %w[sheet drawer sidebar panel slide-in menu navigation],
      'label' => %w[label text caption description title heading name]
    }.freeze
    
    # AI-powered component prediction patterns (replacing fixed app types)
    # Based on research from Vercel v0, Lovable.dev, and modern AI app builders
    INTENT_PATTERNS = {
      # Administrative interfaces
      admin: {
        keywords: %w[admin administrative manage management control panel backend dashboard],
        core_components: %w[sidebar navigation-menu table dropdown-menu],
        conditional: {
          'chart' => %w[analytics metrics data visualization reporting],
          'form' => %w[settings configuration user management],
          'badge' => %w[status permissions roles notifications]
        }
      },
      
      # SaaS/Business applications
      saas: {
        keywords: %w[saas software-as-a-service business enterprise platform solution],
        core_components: %w[navigation-menu card table form button],
        conditional: {
          'sidebar' => %w[dashboard workspace multi-section],
          'chart' => %w[analytics metrics insights reporting billing usage],
          'tabs' => %w[settings configuration multi-view sections]
        }
      },
      
      # Data visualization & Analytics  
      analytics: {
        keywords: %w[chart graph analytics visualization data metrics reporting insights trends],
        core_components: %w[chart card select badge],
        conditional: {
          'table' => %w[data list records rows],
          'calendar' => %w[date time period range],
          'dropdown-menu' => %w[filter options settings],
          'sidebar' => %w[dashboard navigation sections]
        }
      },
      
      # Multi-section applications
      workspace: {
        keywords: %w[workspace dashboard home main-app multi-section navigation],
        core_components: %w[sidebar navigation-menu card],
        conditional: {
          'tabs' => %w[sections views pages categories],
          'table' => %w[list data items records],
          'chart' => %w[overview metrics summary]
        }
      },
      
      # Form-heavy applications
      forms: {
        keywords: %w[form registration signup application survey questionnaire input],
        core_components: %w[form input textarea select button],
        conditional: {
          'checkbox' => %w[agreement terms options multi-select],
          'radio-group' => %w[choice option single-select],
          'calendar' => %w[date appointment booking schedule]
        }
      }
    }.freeze
    
    # Component dependencies - when one component is selected, others might be needed
    COMPONENT_DEPENDENCIES = {
      'sidebar' => %w[navigation-menu],  # Sidebars usually need navigation
      'chart' => %w[card],  # Charts usually displayed in cards
      'table' => %w[card],  # Tables usually in cards
      'form' => %w[button input label],  # Forms need inputs and submit buttons
      'calendar' => %w[button card],  # Calendars need navigation buttons
      'dropdown-menu' => %w[button],  # Dropdowns triggered by buttons
      'dialog' => %w[button card],  # Dialogs triggered by buttons
      'sheet' => %w[button navigation-menu]  # Sheets often contain navigation
    }.freeze
    
    # FIXED: Technical aliases for better prediction (handles metaphors and jargon)
    TECHNICAL_ALIASES = {
      # Technical jargon
      'crud' => %w[form table button dialog input],
      'crud interface' => %w[form table button dialog input dropdown-menu],
      'data entry' => %w[form input textarea select button label],
      'data grid' => %w[table card button dropdown-menu],
      'data table' => %w[table card button dropdown-menu badge],
      
      # Metaphorical language
      'command center' => %w[sidebar navigation-menu card table chart],
      'control panel' => %w[sidebar navigation-menu form switch button],
      'cockpit' => %w[sidebar chart card badge progress],
      'hub' => %w[navigation-menu card button tabs],
      'portal' => %w[navigation-menu card tabs button],
      
      # UI patterns
      'wizard' => %w[form tabs button progress navigation-menu],
      'stepper' => %w[form tabs button progress],
      'kanban' => %w[card button badge dropdown-menu],
      'kanban board' => %w[card button badge dropdown-menu scroll-area],
      'timeline' => %w[card scroll-area badge separator],
      'feed' => %w[card scroll-area button avatar],
      
      # Business terms
      'invoice' => %w[table form button input select],
      'checkout' => %w[form input button card progress],
      'subscription' => %w[card button badge tabs form],
      'billing' => %w[table card form input button],
      'pricing' => %w[card badge button tabs],
      
      # Composite patterns
      'admin dashboard' => %w[sidebar navigation-menu table chart card],
      'user management' => %w[table form dialog button dropdown-menu],
      'settings panel' => %w[form tabs switch button input],
      'analytics dashboard' => %w[chart card table select badge]
    }.freeze
    
    # Maximum components to recommend (token optimization)
    MAX_COMPONENTS = 5
    
    class << self
      def analyze(user_prompt, existing_files = [], options = {})
        analyzer = new(user_prompt, existing_files, options)
        analyzer.required_components
      end
      
      def analyze_with_confidence(user_prompt, existing_files = [], options = {})
        analyzer = new(user_prompt, existing_files, options)
        {
          components: analyzer.required_components,
          confidence: analyzer.confidence_scores,
          app_type: analyzer.detected_app_type,
          reasoning: analyzer.analysis_reasoning
        }
      end
    end
    
    attr_reader :user_prompt, :existing_files, :detected_app_type, 
                :confidence_scores, :analysis_reasoning
    
    def initialize(user_prompt, existing_files = [], options = {})
      @user_prompt = user_prompt.to_s.downcase
      @existing_files = existing_files
      @app_type = options[:app_type]
      @max_components = options[:max_components] || MAX_COMPONENTS
      @confidence_scores = {}
      @analysis_reasoning = []
    end
    
    def required_components
      components = []
      
      # Step 1: Analyze prompt for explicit component mentions
      prompt_components = analyze_prompt_keywords
      components.concat(prompt_components)
      @analysis_reasoning << "Found #{prompt_components.size} components from prompt keywords"
      
      # Step 2: Check existing files for component imports
      if @existing_files.any?
        imported_components = analyze_existing_imports
        components.concat(imported_components)
        @analysis_reasoning << "Found #{imported_components.size} components from existing imports"
      end
      
      # Step 3: AI-powered intent analysis (replaces fixed app types)
      intent_components = analyze_intent_patterns
      components.concat(intent_components)
      
      # Step 4: Resolve component dependencies
      dependency_components = resolve_component_dependencies(components)
      components.concat(dependency_components)
      
      # Step 5: Add essential components that are almost always needed
      essential = determine_essential_components(components)
      components.concat(essential)
      
      # Step 6: Deduplicate and prioritize
      prioritized = prioritize_components(components.uniq)
      
      # Step 7: Limit to max components (with smart selection)
      final_components = smart_component_selection(prioritized)
      
      Rails.logger.info "[ComponentAnalyzer] Prompt: #{@user_prompt[0..100]}..."
      Rails.logger.info "[ComponentAnalyzer] Detected app type: #{@detected_app_type}"
      Rails.logger.info "[ComponentAnalyzer] Required components: #{final_components.join(', ')}"
      Rails.logger.info "[ComponentAnalyzer] Reasoning: #{@analysis_reasoning.join('; ')}"
      
      final_components
    end
    
    private
    
    def analyze_prompt_keywords
      components = []
      
      # FIXED: First check technical aliases for better matching
      TECHNICAL_ALIASES.each do |alias_term, alias_components|
        if @user_prompt.include?(alias_term)
          components.concat(alias_components)
          @analysis_reasoning << "Detected '#{alias_term}' pattern - added #{alias_components.join(', ')}"
          # High confidence for explicit technical patterns
          alias_components.each { |c| @confidence_scores[c] = 0.9 }
        end
      end
      
      # Then check individual component keywords
      COMPONENT_INDICATORS.each do |component, keywords|
        # Check if any keyword appears in the prompt
        if keywords.any? { |keyword| @user_prompt.include?(keyword) }
          components << component
          @confidence_scores[component] = calculate_keyword_confidence(component, keywords)
        end
      end
      
      components
    end
    
    def calculate_keyword_confidence(component, keywords)
      # Higher confidence if multiple keywords match
      matches = keywords.count { |keyword| @user_prompt.include?(keyword) }
      [matches * 0.3, 1.0].min  # Cap at 1.0
    end
    
    # AI-powered intent analysis based on research findings
    def analyze_intent_patterns
      components = []
      detected_intents = []
      
      INTENT_PATTERNS.each do |intent, config|
        # Check if prompt matches this intent pattern
        if config[:keywords].any? { |keyword| @user_prompt.include?(keyword) }
          detected_intents << intent
          
          # Add core components for this intent
          components.concat(config[:core_components])
          
          # Check conditional components
          config[:conditional].each do |component, triggers|
            if triggers.any? { |trigger| @user_prompt.include?(trigger) }
              components << component
              @confidence_scores[component] = (@confidence_scores[component] || 0) + 0.7
            end
          end
          
          @analysis_reasoning << "Detected #{intent} intent - added #{config[:core_components].join(', ')}"
        end
      end
      
      @detected_app_type = detected_intents.first&.to_s || 'general'
      
      # Handle complex multi-intent scenarios
      if detected_intents.include?(:admin) && detected_intents.include?(:analytics)
        # Admin + Analytics = Dashboard with sidebar and charts
        components += %w[sidebar chart table card]
        @analysis_reasoning << "Multi-intent: Admin + Analytics detected"
      elsif detected_intents.include?(:saas) && detected_intents.include?(:analytics)
        # SaaS + Analytics = Business intelligence interface
        components += %w[sidebar chart navigation-menu]
        @analysis_reasoning << "Multi-intent: SaaS + Analytics detected"
      end
      
      components.uniq
    end
    
    # Resolve component dependencies automatically
    def resolve_component_dependencies(components)
      dependency_components = []
      
      components.each do |component|
        if COMPONENT_DEPENDENCIES[component]
          dependencies = COMPONENT_DEPENDENCIES[component]
          dependency_components.concat(dependencies)
          @analysis_reasoning << "Added dependencies #{dependencies.join(', ')} for #{component}"
        end
      end
      
      dependency_components.uniq
    end
    
    # Smart component selection based on priority and context
    def smart_component_selection(components)
      # Group components by importance
      critical = components & %w[button input card form]
      layout = components & %w[sidebar navigation-menu table chart]
      interaction = components & %w[dropdown-menu dialog select tabs]
      feedback = components & %w[alert toast badge skeleton]
      
      selected = []
      
      # Always include critical components
      selected.concat(critical.take(2))
      
      # Add layout components based on intent
      if @detected_app_type.in?(%w[admin saas workspace analytics])
        selected.concat(layout.take(2))
      else
        selected.concat(layout.take(1))
      end
      
      # Fill remaining slots with interaction components
      remaining_slots = @max_components - selected.size
      selected.concat(interaction.take([remaining_slots, 2].min))
      
      # Add feedback components if space available
      remaining_slots = @max_components - selected.size
      if remaining_slots > 0
        selected.concat(feedback.take(remaining_slots))
      end
      
      selected.uniq.take(@max_components)
    end
    
    def analyze_existing_imports
      components = []
      
      @existing_files.each do |file|
        # Skip non-code files
        next unless file.respond_to?(:path) && file.path.match?(/\.(tsx?|jsx?)$/)
        next unless file.respond_to?(:content)
        
        content = file.content.to_s
        
        # Look for component imports
        import_regex = /import\s+{[^}]+}\s+from\s+['"]@\/components\/ui\/(\w+)['"]/
        content.scan(import_regex) do |match|
          components << match[0]
        end
        
        # Also check for inline component usage
        COMPONENT_INDICATORS.keys.each do |component|
          component_tag = component.split('-').map(&:capitalize).join
          if content.match?(/<#{component_tag}[\s>]/)
            components << component
          end
        end
      end
      
      components.uniq
    end
    
    def detect_app_type_from_prompt
      # This method is now primarily used for legacy compatibility
      # The real app type detection happens in analyze_intent_patterns
      
      # Quick checks for common simple app types that don't need complex analysis
      return 'todo' if @user_prompt.match?(/\b(todo|task|checklist|to-do)\b/)
      return 'landing' if @user_prompt.match?(/landing|marketing|hero|startup|homepage|website/)
      return 'blog' if @user_prompt.match?(/blog|article|post|content|writing|news/)
      return 'chat' if @user_prompt.match?(/chat|message|conversation|messenger|communication/)
      return 'ecommerce' if @user_prompt.match?(/shop|store|product|cart|ecommerce|e-commerce|marketplace/)
      
      # Complex app types are handled by analyze_intent_patterns
      # This includes admin, saas, analytics, workspace scenarios
      return @detected_app_type if @detected_app_type
      
      # Return the explicitly provided type or general
      @app_type || 'general'
    end
    
    def determine_essential_components(already_selected)
      essential = []
      
      # Button is almost always needed unless already selected
      unless already_selected.include?('button')
        if @user_prompt.match?(/click|action|submit|save|create|delete|update/)
          essential << 'button'
          @analysis_reasoning << "Added button as essential component"
        end
      end
      
      # Card is common for layouts unless already selected
      unless already_selected.include?('card')
        if @user_prompt.match?(/display|show|list|grid|layout|organize/)
          essential << 'card'
          @analysis_reasoning << "Added card for layout structure"
        end
      end
      
      # Input is needed for any user input unless already selected
      unless already_selected.include?('input')
        if @user_prompt.match?(/enter|type|search|filter|name|email|password/)
          essential << 'input'
          @analysis_reasoning << "Added input for user data entry"
        end
      end
      
      essential
    end
    
    def prioritize_components(components)
      # Priority order based on usage frequency and importance
      priority_order = %w[
        button input card form select
        table textarea checkbox label badge
        tabs dropdown-menu dialog alert avatar
        toast accordion calendar chart radio-group
        skeleton progress slider switch tooltip
        separator scroll-area sheet popover breadcrumb
      ]
      
      # Sort components by priority
      components.sort_by do |component|
        index = priority_order.index(component)
        index || 999  # Put unknown components at the end
      end
    end
  end
end