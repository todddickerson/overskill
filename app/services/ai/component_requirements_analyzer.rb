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
    
    # App type to component mappings (fallback when prompt analysis isn't clear)
    APP_TYPE_DEFAULTS = {
      'todo' => %w[input checkbox button card label],
      'landing' => %w[button card badge tabs separator],
      'dashboard' => %w[card table chart select dropdown-menu],
      'form' => %w[form input textarea select button],
      'ecommerce' => %w[card button badge input select],
      'blog' => %w[card button badge separator scroll-area],
      'chat' => %w[input button card avatar scroll-area],
      'analytics' => %w[card chart table select badge],
      'settings' => %w[form input select switch button],
      'profile' => %w[card avatar input button tabs]
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
      
      # Step 3: Detect app type and add defaults if needed
      @detected_app_type = detect_app_type_from_prompt
      if components.size < 3 && @detected_app_type != 'unknown'
        type_defaults = APP_TYPE_DEFAULTS[@detected_app_type] || []
        components.concat(type_defaults)
        @analysis_reasoning << "Added #{type_defaults.size} default components for #{@detected_app_type} app"
      end
      
      # Step 4: Add essential components that are almost always needed
      essential = determine_essential_components(components)
      components.concat(essential)
      
      # Step 5: Deduplicate and prioritize
      prioritized = prioritize_components(components.uniq)
      
      # Step 6: Limit to max components
      final_components = prioritized.take(@max_components)
      
      Rails.logger.info "[ComponentAnalyzer] Prompt: #{@user_prompt[0..100]}..."
      Rails.logger.info "[ComponentAnalyzer] Detected app type: #{@detected_app_type}"
      Rails.logger.info "[ComponentAnalyzer] Required components: #{final_components.join(', ')}"
      Rails.logger.info "[ComponentAnalyzer] Reasoning: #{@analysis_reasoning.join('; ')}"
      
      final_components
    end
    
    private
    
    def analyze_prompt_keywords
      components = []
      
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
      # Check for app type indicators in order of specificity
      return 'todo' if @user_prompt.match?(/todo|task|checklist|to-do/)
      return 'dashboard' if @user_prompt.match?(/dashboard|analytics|metrics|admin|panel/)
      return 'ecommerce' if @user_prompt.match?(/shop|store|product|cart|ecommerce|e-commerce|marketplace/)
      return 'form' if @user_prompt.match?(/form|survey|registration|signup|sign-up|application/)
      return 'landing' if @user_prompt.match?(/landing|marketing|hero|startup|homepage|website/)
      return 'blog' if @user_prompt.match?(/blog|article|post|content|writing|news/)
      return 'chat' if @user_prompt.match?(/chat|message|conversation|messenger|communication/)
      return 'analytics' if @user_prompt.match?(/analytics|chart|graph|visualization|report/)
      return 'settings' if @user_prompt.match?(/settings|preferences|configuration|options/)
      return 'profile' if @user_prompt.match?(/profile|account|user|personal/)
      
      # Return the explicitly provided type or unknown
      @app_type || 'unknown'
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