module Ai
  class FileContextAnalyzer
    # Analyzes current app state to make intelligent modifications
    # Understands file structure, components, routes, database schema, etc.

    def initialize(app)
      @app = app
    end

    def analyze
      Rails.logger.info "[FileContextAnalyzer] Analyzing app ##{@app.id} with #{@app.app_files.count} files"

      analysis = {
        # Current file structure and contents
        file_structure: build_file_tree,

        # Components and their purposes
        existing_components: identify_existing_components,

        # Current dependencies and libraries
        dependencies: parse_package_json,

        # Routing structure
        routes: analyze_routing_structure,

        # Database schema (from app-scoped tables)
        database_schema: infer_database_schema,

        # UI patterns and styling approach
        ui_patterns: analyze_ui_patterns,

        # Recent changes and conversation history
        recent_changes: get_recent_file_changes,

        # Potential improvement areas
        suggestions: generate_improvement_suggestions,

        # Analysis metadata
        analyzed_at: Time.current.iso8601,
        analysis_version: "1.0"
      }

      Rails.logger.info "[FileContextAnalyzer] Analysis complete: #{analysis[:existing_components].keys.count} components, #{analysis[:routes].count} routes"
      analysis
    rescue => e
      Rails.logger.error "[FileContextAnalyzer] Analysis failed for app ##{@app.id}: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")

      # Return basic structure even on failure
      {
        file_structure: {total_files: @app.app_files.count},
        existing_components: {},
        error: e.message
      }
    end

    private

    def build_file_tree
      files = @app.app_files.select(:path, :content).order(:path)

      structure = {
        total_files: files.count,
        by_type: {},
        by_directory: {},
        framework_files: [],
        app_files: []
      }

      files.each do |file|
        # Categorize by file extension
        extension = ::File.extname(file.path).downcase.delete(".")
        extension = "typescript" if %w[ts tsx].include?(extension)
        extension = "javascript" if %w[js jsx].include?(extension)

        structure[:by_type][extension] ||= []
        structure[:by_type][extension] << file.path

        # Categorize by directory
        directory = ::File.dirname(file.path)
        directory = "root" if directory == "."

        structure[:by_directory][directory] ||= []
        structure[:by_directory][directory] << file.path

        # Separate framework files from app-specific files
        if framework_file?(file.path)
          structure[:framework_files] << file.path
        else
          structure[:app_files] << file.path
        end
      end

      structure
    end

    def framework_file?(path)
      framework_patterns = [
        /^package\.json$/,
        /^vite\.config\./,
        /^tsconfig\./,
        /^tailwind\.config\./,
        /^postcss\.config\./,
        /^\.env/,
        /^index\.html$/,
        /^src\/main\./,
        /^src\/index\./,
        /^src\/App\./,
        /^src\/lib\//,
        /^src\/types\//,
        /^src\/hooks\/useAuth\./
      ]

      framework_patterns.any? { |pattern| path.match?(pattern) }
    end

    def identify_existing_components
      components = {}

      component_files = @app.app_files.where("path LIKE 'src/components/%' AND path LIKE '%.tsx'")
      page_files = @app.app_files.where("path LIKE 'src/pages/%' AND path LIKE '%.tsx'")

      (component_files + page_files).each do |file|
        component_info = analyze_component_file(file)
        components[component_info[:name]] = component_info
      end

      components
    end

    def analyze_component_file(file)
      content = file.content || ""

      component_info = {
        name: extract_component_name(file.path),
        path: file.path,
        type: classify_component_type(content, file.path),
        props: extract_component_props(content),
        dependencies: extract_imports(content),
        purpose: infer_component_purpose(content, file.path),
        complexity: calculate_component_complexity(content),
        reusable: assess_reusability(content, file.path),
        ui_framework: detect_ui_framework(content),
        state_management: detect_state_management(content),
        database_usage: detect_database_usage(content)
      }

      Rails.logger.debug "[FileContextAnalyzer] Analyzed component: #{component_info[:name]} (#{component_info[:type]})"
      component_info
    end

    def extract_component_name(path)
      ::File.basename(path, ".*")
    end

    def classify_component_type(content, path)
      if path.include?("src/pages/")
        :page
      elsif path.include?("src/components/ui/")
        :ui_component
      elsif path.include?("src/components/auth/")
        :auth_component
      elsif content.match?(/export default function|const \w+ = \(\) =>/i)
        if content.include?("useState") || content.include?("useEffect")
          :stateful_component
        else
          :stateless_component
        end
      elsif content.include?("useHook") || path.include?("hooks/")
        :hook
      else
        :utility
      end
    end

    def extract_component_props(content)
      props = []

      # Look for TypeScript interface definitions
      interface_matches = content.scan(/interface \w+Props\s*\{([^}]+)\}/m)
      interface_matches.each do |match|
        prop_lines = match[0].split("\n").map(&:strip).reject(&:empty?)
        prop_lines.each do |line|
          prop_match = line.match(/(\w+)[\?\:]?\s*:\s*([^;,\n]+)/)
          if prop_match
            props << {
              name: prop_match[1],
              type: prop_match[2].strip,
              optional: line.include?("?")
            }
          end
        end
      end

      # Look for destructured props in function signature
      prop_destructure = content.match(/function \w+\(\{\s*([^}]+)\s*\}/)
      if prop_destructure
        prop_names = prop_destructure[1].split(",").map(&:strip)
        prop_names.each do |name|
          props << {name: name, type: "unknown", optional: false} unless props.any? { |p| p[:name] == name }
        end
      end

      props
    end

    def extract_imports(content)
      imports = []

      # Extract all import statements
      import_lines = content.scan(/^import\s+.*?from\s+['"][^'"]+['"];?/m)

      import_lines.each do |import_line|
        # Extract package name
        package_match = import_line.match(/from\s+['"]([^'"]+)['"]/)
        next unless package_match

        package = package_match[1]

        # Classify import type
        import_type = if package.start_with?(".")
          :local
        elsif package.start_with?("@")
          :scoped_package
        else
          :npm_package
        end

        imports << {
          package: package,
          type: import_type,
          statement: import_line.strip
        }
      end

      imports
    end

    def infer_component_purpose(content, path)
      # Analyze content and path to infer component purpose
      purposes = []

      # Path-based inference
      if path.include?("auth")
        purposes << "authentication"
      elsif path.include?("todo") || path.include?("task")
        purposes << "task_management"
      elsif path.include?("chat") || path.include?("message")
        purposes << "messaging"
      elsif path.include?("dashboard")
        purposes << "dashboard"
      elsif path.include?("nav")
        purposes << "navigation"
      end

      # Content-based inference
      if content.include?("login") || content.include?("signin")
        purposes << "authentication"
      elsif content.include?("todo") || content.include?("task")
        purposes << "task_management"
      elsif content.include?("chat") || content.include?("message")
        purposes << "messaging"
      elsif content.include?("supabase") || content.include?("db.from")
        purposes << "data_management"
      elsif content.include?("form") || content.include?("input")
        purposes << "form_handling"
      end

      purposes.empty? ? ["general"] : purposes
    end

    def calculate_component_complexity(content)
      lines = content.lines.count

      complexity_score = 0
      complexity_score += lines / 10 # Base complexity from line count
      complexity_score += content.scan(/useState|useEffect|useReducer/).count * 2 # State management
      complexity_score += content.scan(/if\s*\(|switch\s*\(/).count # Conditional logic
      complexity_score += content.scan(/\.map\(|\.filter\(|\.reduce\(/).count # Array operations
      complexity_score += content.scan(/async|await|Promise/).count # Async operations

      case complexity_score
      when 0..5
        :simple
      when 6..15
        :moderate
      else
        :complex
      end
    end

    def assess_reusability(content, path)
      # Assess how reusable this component is
      reusability_score = 0

      # UI components are generally more reusable
      reusability_score += 2 if path.include?("components/ui/")

      # Components with props are more reusable
      reusability_score += 1 if content.include?("props") || content.include?("Props")

      # Generic names suggest reusability
      generic_names = %w[button card modal input form table list item]
      component_name = extract_component_name(path).downcase
      reusability_score += 2 if generic_names.any? { |name| component_name.include?(name) }

      # Hardcoded values reduce reusability
      reusability_score -= 1 if content.scan(/'[^']*'|"[^"]*"/).count > 5

      # Business logic reduces reusability
      reusability_score -= 1 if content.include?("supabase") || content.include?("api")

      case reusability_score
      when ..0
        :low
      when 1..3
        :moderate
      else
        :high
      end
    end

    def detect_ui_framework(content)
      frameworks = []

      frameworks << "tailwind" if content.include?("className") && content.match?(/className="[^"]*\b(bg-|text-|p-|m-|w-|h-)/i)
      frameworks << "shadcn_ui" if content.include?("@/components/ui/") || content.include?("shadcn")
      frameworks << "supabase_ui" if content.include?("supabase") && content.include?("ui")
      frameworks << "react_router" if content.include?("useNavigate") || content.include?("Link")

      frameworks.empty? ? ["react"] : frameworks
    end

    def detect_state_management(content)
      state_patterns = []

      state_patterns << "useState" if content.include?("useState")
      state_patterns << "useEffect" if content.include?("useEffect")
      state_patterns << "useReducer" if content.include?("useReducer")
      state_patterns << "useContext" if content.include?("useContext")
      state_patterns << "custom_hooks" if content.match?(/use[A-Z]\w+/)

      state_patterns
    end

    def detect_database_usage(content)
      db_patterns = []

      db_patterns << "supabase" if content.include?("supabase")
      db_patterns << "app_scoped_db" if content.include?("app-scoped-db") || content.include?("db.from")
      db_patterns << "rest_api" if content.include?("fetch") || content.include?("axios")
      db_patterns << "realtime" if content.include?("realtime") || content.include?("subscribe")

      db_patterns
    end

    def parse_package_json
      package_file = @app.app_files.find_by(path: "package.json")
      return {} unless package_file

      begin
        package_data = JSON.parse(package_file.content)

        {
          dependencies: package_data["dependencies"] || {},
          dev_dependencies: package_data["devDependencies"] || {},
          scripts: package_data["scripts"] || {},
          framework_analysis: analyze_dependencies(package_data["dependencies"] || {})
        }
      rescue JSON::ParserError => e
        Rails.logger.error "[FileContextAnalyzer] Failed to parse package.json: #{e.message}"
        {}
      end
    end

    def analyze_dependencies(dependencies)
      analysis = {
        ui_frameworks: [],
        state_management: [],
        routing: [],
        database: [],
        auth: [],
        build_tools: []
      }

      dependencies.each do |package, version|
        case package
        when /react/
          analysis[:ui_frameworks] << "react"
        when /tailwind|@tailwindcss/
          analysis[:ui_frameworks] << "tailwind"
        when /@radix-ui|shadcn/
          analysis[:ui_frameworks] << "shadcn_ui"
        when /supabase/
          analysis[:database] << "supabase"
          analysis[:auth] << "supabase_auth"
        when /router|routing/
          analysis[:routing] << package
        when /redux|zustand|jotai/
          analysis[:state_management] << package
        when /vite|webpack|rollup/
          analysis[:build_tools] << package
        end
      end

      analysis
    end

    def analyze_routing_structure
      router_file = @app.app_files.find_by(path: "src/router.tsx")
      return {} unless router_file

      routes = extract_routes_from_content(router_file.content)

      {
        total_routes: routes.count,
        routes: routes,
        router_type: detect_router_type(router_file.content),
        protected_routes: routes.count { |r| r[:protected] },
        public_routes: routes.count { |r| !r[:protected] }
      }
    end

    def extract_routes_from_content(content)
      routes = []

      # Look for React Router route definitions
      route_matches = content.scan(/<Route\s+path="([^"]+)"[^>]*element=\{[^}]*<([^}\s>]+)/)

      route_matches.each do |match|
        path, component = match

        routes << {
          path: path,
          component: component,
          protected: content.include?("ProtectedRoute") && content.match?(/ProtectedRoute[^>]*#{Regexp.escape(component)}/),
          type: classify_route_type(path)
        }
      end

      # Fallback: Look for path definitions in any format
      if routes.empty?
        path_matches = content.scan(/['"]\/[^'"]*['"]/)
        path_matches.each do |path_match|
          path = path_match.gsub(/['"]/, "")
          routes << {
            path: path,
            component: "unknown",
            protected: false,
            type: classify_route_type(path)
          }
        end
      end

      routes
    end

    def classify_route_type(path)
      case path
      when /auth|login|signup/i
        :auth
      when /dashboard|admin/i
        :protected
      when /profile|settings/i
        :user
      when /^\/$|home/i
        :public
      else
        :general
      end
    end

    def detect_router_type(content)
      if content.include?("BrowserRouter")
        "react_router_browser"
      elsif content.include?("HashRouter")
        "react_router_hash"
      elsif content.include?("Router")
        "react_router"
      else
        "unknown"
      end
    end

    def infer_database_schema
      # Analyze database interactions in components to infer schema
      db_interactions = []

      files_with_db = @app.app_files.where("content LIKE '%db.from%' OR content LIKE '%supabase%'")

      files_with_db.find_each do |file|
        interactions = extract_database_calls(file.content)
        db_interactions.concat(interactions)
      end

      schema = build_schema_from_interactions(db_interactions)

      {
        tables: schema,
        total_tables: schema.keys.count,
        interaction_count: db_interactions.count
      }
    end

    def extract_database_calls(content)
      interactions = []

      # Look for db.from('table') calls
      db_from_matches = content.scan(/db\.from\(['"]([^'"]+)['"]\)/)
      db_from_matches.each do |match|
        table_name = match[0]

        interactions << {
          table: table_name,
          operation: detect_operation_context(content, table_name),
          file_context: "component"
        }
      end

      # Look for supabase.from('table') calls
      supabase_matches = content.scan(/supabase\.from\(['"]([^'"]+)['"]\)/)
      supabase_matches.each do |match|
        table_name = match[0]

        interactions << {
          table: table_name,
          operation: detect_operation_context(content, table_name),
          file_context: "direct_supabase"
        }
      end

      interactions
    end

    def detect_operation_context(content, table_name)
      # Look for CRUD operations around the table usage
      table_context = begin
        content[content.index(table_name) - 100, 200]
      rescue
        content
      end

      operations = []
      operations << "select" if table_context.include?(".select")
      operations << "insert" if table_context.include?(".insert")
      operations << "update" if table_context.include?(".update")
      operations << "delete" if table_context.include?(".delete")
      operations << "subscribe" if table_context.include?(".subscribe")

      operations.empty? ? ["unknown"] : operations
    end

    def build_schema_from_interactions(interactions)
      schema = {}

      interactions.each do |interaction|
        table = interaction[:table]
        schema[table] ||= {
          operations: [],
          inferred_purpose: infer_table_purpose(table),
          usage_count: 0
        }

        schema[table][:operations].concat(interaction[:operation])
        schema[table][:operations].uniq!
        schema[table][:usage_count] += 1
      end

      schema
    end

    def infer_table_purpose(table_name)
      # Remove app scoping prefix if present
      clean_name = table_name.gsub(/^app_\d+_/, "")

      case clean_name
      when /todo|task/i
        "task_management"
      when /user|profile/i
        "user_data"
      when /message|chat/i
        "messaging"
      when /post|comment/i
        "content"
      when /order|payment/i
        "commerce"
      else
        "general_data"
      end
    end

    def analyze_ui_patterns
      {
        styling_approach: detect_styling_approach,
        component_patterns: detect_component_patterns,
        layout_patterns: detect_layout_patterns,
        interaction_patterns: detect_interaction_patterns
      }
    end

    def detect_styling_approach
      approaches = []

      # Check for Tailwind usage
      files_with_tailwind = @app.app_files.where("content LIKE '%className%'").count
      approaches << "tailwind" if files_with_tailwind > 0

      # Check for CSS modules
      css_files = @app.app_files.where("path LIKE '%.css' OR path LIKE '%.scss'").count
      approaches << "css_files" if css_files > 0

      # Check for styled-components or similar
      styled_components = @app.app_files.where("content LIKE '%styled%'").count
      approaches << "styled_components" if styled_components > 0

      approaches.empty? ? ["inline_styles"] : approaches
    end

    def detect_component_patterns
      patterns = []

      # Check for common component patterns
      ui_components = @app.app_files.where("path LIKE 'src/components/ui/%'").count
      patterns << "component_library" if ui_components > 3

      auth_components = @app.app_files.where("path LIKE 'src/components/auth/%'").count
      patterns << "auth_components" if auth_components > 1

      # Check for custom hooks
      custom_hooks = @app.app_files.where("path LIKE 'src/hooks/%' OR content LIKE '%useEffect%'").count
      patterns << "custom_hooks" if custom_hooks > 1

      patterns
    end

    def detect_layout_patterns
      patterns = []

      # Check for layout components
      layout_files = @app.app_files.where("path LIKE '%Layout%' OR path LIKE '%layout%'").count
      patterns << "layout_components" if layout_files > 0

      # Check for navigation
      nav_files = @app.app_files.where("path LIKE '%Nav%' OR path LIKE '%nav%'").count
      patterns << "navigation" if nav_files > 0

      patterns
    end

    def detect_interaction_patterns
      patterns = []

      # Check for form handling
      forms = @app.app_files.where("content LIKE '%form%' OR content LIKE '%Form%'").count
      patterns << "form_handling" if forms > 0

      # Check for modal/dialog usage
      modals = @app.app_files.where("content LIKE '%modal%' OR content LIKE '%dialog%'").count
      patterns << "modal_interactions" if modals > 0

      patterns
    end

    def get_recent_file_changes
      # Get recent file modifications from app versions
      recent_versions = @app.app_versions.includes(:app_version_files)
        .where("created_at >= ?", 1.day.ago)
        .limit(5)

      changes = []

      recent_versions.each do |version|
        version.app_version_files.each do |version_file|
          changes << {
            file_path: version_file.app_file.path,
            action: version_file.action,
            version: version.version_number,
            created_at: version.created_at.iso8601
          }
        end
      end

      changes.sort_by { |c| c[:created_at] }.reverse
    end

    def generate_improvement_suggestions
      suggestions = []

      # Analyze current state and suggest improvements
      file_count = @app.app_files.count

      if file_count < 10
        suggestions << {
          type: "expansion",
          priority: "low",
          suggestion: "Consider adding more components to improve code organization",
          rationale: "Small apps benefit from component separation"
        }
      end

      # Check for missing common patterns
      has_auth = @app.app_files.where("path LIKE '%auth%'").exists?
      unless has_auth
        suggestions << {
          type: "feature_addition",
          priority: "medium",
          suggestion: "Add user authentication system",
          rationale: "Most apps benefit from user management"
        }
      end

      # Check for TypeScript usage
      ts_files = @app.app_files.where("path LIKE '%.tsx' OR path LIKE '%.ts'").count
      js_files = @app.app_files.where("path LIKE '%.jsx' OR path LIKE '%.js'").count

      if js_files > ts_files
        suggestions << {
          type: "code_quality",
          priority: "low",
          suggestion: "Consider migrating to TypeScript for better type safety",
          rationale: "TypeScript provides better development experience"
        }
      end

      suggestions
    end
  end
end
