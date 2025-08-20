module Validation
  class ComponentImportValidator
    attr_reader :app, :errors, :warnings
    
    def initialize(app)
      @app = app
      @errors = []
      @warnings = []
    end
    
    def validate!
      Rails.logger.info "[ComponentImportValidator] Validating component imports for app #{app.id}"
      @errors.clear
      @warnings.clear
      
      # Find the main App.tsx file
      app_tsx = app.app_files.find_by(path: "src/App.tsx")
      return unless app_tsx
      
      validate_tsx_file(app_tsx)
      
      # Check other TSX files that might have missing imports
      app.app_files.where("path LIKE '%.tsx' AND path != 'src/App.tsx'").each do |file|
        validate_tsx_file(file)
      end
      
      log_results
      
      @errors.empty?
    end
    
    def validate_tsx_file(file)
      content = file.content
      return unless content.present?
      
      # Extract imports
      import_lines = extract_imports(content)
      imported_components = extract_imported_component_names(import_lines)
      
      # Find component usages in JSX
      component_usages = extract_jsx_component_usages(content)
      
      # Find components defined in the same file
      locally_defined_components = extract_local_component_definitions(content)
      
      # Check for missing imports (exclude locally defined components)
      missing_imports = component_usages - imported_components - locally_defined_components
      
      # Filter out built-in HTML elements and known globals
      missing_imports = filter_false_positives(missing_imports)
      
      if missing_imports.any?
        @errors << {
          file: file.path,
          type: :missing_imports,
          missing_components: missing_imports,
          message: "Missing imports for components: #{missing_imports.join(', ')}"
        }
        
        # Try to suggest import paths
        missing_imports.each do |component|
          suggested_import = suggest_import_path(component)
          if suggested_import
            @warnings << {
              file: file.path,
              type: :suggested_import,
              component: component,
              suggestion: suggested_import,
              message: "Suggested import for #{component}: #{suggested_import}"
            }
          end
        end
      end
    end
    
    private
    
    def extract_imports(content)
      content.lines.select { |line| line.strip.start_with?('import ') }
    end
    
    def extract_imported_component_names(import_lines)
      components = []
      
      import_lines.each do |line|
        # Handle default imports: import Component from "..."
        if match = line.match(/import\s+(\w+)\s+from/)
          components << match[1]
        end
        
        # Handle named imports: import { Component1, Component2 } from "..."
        if match = line.match(/import\s+\{\s*([^}]+)\s*\}\s+from/)
          named_imports = match[1].split(',').map { |name| name.strip.gsub(/\s+as\s+\w+/, '') }
          components.concat(named_imports)
        end
        
        # Handle mixed imports: import Default, { Named1, Named2 } from "..."
        if match = line.match(/import\s+(\w+),\s*\{\s*([^}]+)\s*\}\s+from/)
          components << match[1]
          named_imports = match[2].split(',').map { |name| name.strip.gsub(/\s+as\s+\w+/, '') }
          components.concat(named_imports)
        end
      end
      
      components.uniq
    end
    
    def extract_jsx_component_usages(content)
      components = Set.new
      
      # Find JSX elements that start with capital letters (React components)
      content.scan(/<(\w+)(?:\s|\/|>)/) do |match|
        component_name = match[0]
        if component_name[0].match?(/[A-Z]/) # React components start with capital letters
          components.add(component_name)
        end
      end
      
      # Also check self-closing tags
      content.scan(/<(\w+)\s*\/?>/) do |match|
        component_name = match[0]
        if component_name[0].match?(/[A-Z]/)
          components.add(component_name)
        end
      end
      
      components.to_a
    end
    
    def extract_local_component_definitions(content)
      components = Set.new
      
      # Find function components: function ComponentName() or function ComponentName(
      content.scan(/function\s+([A-Z]\w*)\s*\(/) do |match|
        components.add(match[0])
      end
      
      # Find arrow function components: const ComponentName = () => or const ComponentName: React.FC =
      content.scan(/const\s+([A-Z]\w*)\s*[=:][^=]*(?:=>|React\.FC|FunctionComponent)/) do |match|
        components.add(match[0])
      end
      
      # Find class components: class ComponentName extends
      content.scan(/class\s+([A-Z]\w*)\s+extends/) do |match|
        components.add(match[0])
      end
      
      components.to_a
    end
    
    def filter_false_positives(components)
      # Remove built-in HTML elements that might be capitalized
      html_elements = %w[
        HTML HEAD BODY DIV SPAN P H1 H2 H3 H4 H5 H6 A IMG INPUT BUTTON
        FORM TABLE TR TD TH UL OL LI SELECT OPTION TEXTAREA LABEL
      ]
      
      # Remove React built-ins and common library components
      react_builtins = %w[Fragment StrictMode Suspense]
      
      # Remove Router components (commonly used)
      router_components = %w[Router Routes Route Link NavLink Navigate Outlet]
      
      # Remove UI library components that are commonly available globally
      ui_components = %w[Toaster Sonner QueryClient QueryClientProvider ThemeProvider]
      
      # Remove TypeScript types and HTML element types (these end with Element or are all caps)
      typescript_types = components.select do |comp|
        comp.end_with?('Element') || # HTMLDivElement, HTMLButtonElement, etc.
        comp.end_with?('Props') ||   # ComponentProps, etc.
        comp.end_with?('Value') ||   # ContextValue, etc.
        comp.end_with?('Provider') ||# Already covered above but being explicit
        comp.match?(/^[A-Z_]+$/) ||  # All caps like FormData (browser global)
        comp.match?(/^T[A-Z]/)       # TypeScript generic type conventions like TFieldValues
      end
      
      # Remove UI library internals (things that are typically provided by the library)
      ui_internals = %w[
        CarouselContextProps ChartContextProps ChartContainer ChartStyle
        AlertDialogPortal AlertDialogOverlay DialogPortal DialogOverlay
        DrawerPortal DrawerOverlay SheetPortal SheetOverlay
        CommandPrimitive NavigationMenuViewport PaginationLink ScrollBar
        SelectScrollUpButton SelectScrollDownButton SidebarContext
        TooltipProvider TooltipTrigger TooltipContent 
        ToastProvider ToastTitle ToastDescription ToastClose ToastViewport
        FormField FormItemContextValue FormFieldContextValue Controller
      ]
      
      # Special handling for inline components (defined in the same file)
      exclude_list = html_elements + react_builtins + router_components + ui_components + typescript_types + ui_internals
      
      components.reject { |comp| exclude_list.include?(comp) }
    end
    
    def suggest_import_path(component_name)
      # Look for the component in the app's files
      possible_files = app.app_files.where("path LIKE ? OR path LIKE ?", 
                                          "%/#{component_name}.tsx", 
                                          "%/#{component_name}.jsx")
      
      if possible_files.any?
        file = possible_files.first
        # Convert file path to import path
        import_path = file.path.gsub(/^src\//, './').gsub(/\.(tsx|jsx)$/, '')
        "import #{component_name} from \"#{import_path}\";"
      elsif component_name.match?(/^[A-Z][a-z]+$/) # Looks like a component name
        # Suggest common locations
        possible_paths = [
          "./components/#{component_name}",
          "./pages/#{component_name}",
          "./components/ui/#{component_name.downcase}"
        ]
        "import #{component_name} from \"#{possible_paths.first}\"; // Check: #{possible_paths.join(', ')}"
      else
        nil
      end
    end
    
    def log_results
      if @errors.any?
        Rails.logger.warn "[ComponentImportValidator] Found #{@errors.size} import errors:"
        @errors.each do |error|
          Rails.logger.warn "  #{error[:file]}: #{error[:message]}"
        end
      end
      
      if @warnings.any?
        Rails.logger.info "[ComponentImportValidator] Import suggestions:"
        @warnings.each do |warning|
          Rails.logger.info "  #{warning[:file]}: #{warning[:message]}"
        end
      end
      
      if @errors.empty?
        Rails.logger.info "[ComponentImportValidator] All component imports are valid"
      end
    end
  end
end