module Ai
  class OptionalComponentService
    def initialize(app)
      @app = app
    end
    
    # Get available optional component categories for AI to choose from
    def available_component_categories
      {
        'shadcn_ui_core' => {
          description: 'Core shadcn/ui components (Button, Card, Input, Dialog, etc.)',
          components: SHADCN_CORE_COMPONENTS,
          dependencies: ['@radix-ui/react-dialog', '@radix-ui/react-slot', 'class-variance-authority']
        },
        'shadcn_ui_forms' => {
          description: 'Form-focused shadcn/ui components (Form validation, Date Picker, Combobox)',
          components: SHADCN_FORM_COMPONENTS,
          dependencies: ['@hookform/resolvers', 'react-hook-form', 'zod', '@radix-ui/react-popover']
        },
        'shadcn_ui_data' => {
          description: 'Data display components (Data Table, Charts, Progress)',
          components: SHADCN_DATA_COMPONENTS,
          dependencies: ['@tanstack/react-table', 'recharts', '@radix-ui/react-progress']
        },
        'shadcn_ui_navigation' => {
          description: 'Navigation and layout components (Sidebar, Navigation Menu, Breadcrumb)',
          components: SHADCN_NAVIGATION_COMPONENTS,
          dependencies: ['@radix-ui/react-navigation-menu', '@radix-ui/react-separator']
        },
        'shadcn_blocks' => {
          description: 'Pre-built page blocks (Login forms, Dashboard layouts, Sidebar patterns)',
          components: SHADCN_BLOCKS,
          dependencies: [] # Blocks use existing ui components
        }
      }
    end
    
    # Add specific component category to the app
    def add_component_category(category_key)
      category = available_component_categories[category_key]
      return false unless category
      
      Rails.logger.info "[OptionalComponentService] Adding #{category_key} components to app ##{@app.id}"
      
      # Add dependencies to package.json if needed
      add_category_dependencies(category[:dependencies]) if category[:dependencies].any?
      
      # Add component files
      category[:components].each do |component_name, component_info|
        create_component_file(component_name, component_info, category_key)
      end
      
      Rails.logger.info "[OptionalComponentService] Added #{category[:components].size} components from #{category_key}"
      true
    end
    
    # Generate AI context about available components
    def generate_ai_context
      context = []
      context << "## Available Optional Component Libraries"
      context << ""
      context << "The following component libraries are available to enhance your app:"
      context << ""
      
      available_component_categories.each do |key, category|
        context << "### #{key.humanize}"
        context << category[:description]
        context << ""
        context << "Available components:"
        category[:components].each do |component, info|
          context << "- **#{component}**: #{info[:description]}"
        end
        context << ""
        context << "To use: Ask me to 'add #{key} components' to include this entire category."
        context << ""
      end
      
      context << "## Usage Examples:"
      context << "- 'Add shadcn ui core components for better buttons and dialogs'"
      context << "- 'Include form components for advanced form validation'"
      context << "- 'Add navigation components for a professional sidebar'"
      context << ""
      
      context.join("\n")
    end
    
    private
    
    # Core shadcn/ui components most apps need
    SHADCN_CORE_COMPONENTS = {
      'button' => {
        description: 'Flexible button with variants (default, destructive, outline, secondary, ghost, link)',
        path: 'src/components/ui/button.tsx',
        template_source: 'shadcn_ui/button.tsx'
      },
      'card' => {
        description: 'Card container with header, content, and footer sections',
        path: 'src/components/ui/card.tsx', 
        template_source: 'shadcn_ui/card.tsx'
      },
      'input' => {
        description: 'Styled input field with proper focus states',
        path: 'src/components/ui/input.tsx',
        template_source: 'shadcn_ui/input.tsx'
      },
      'dialog' => {
        description: 'Modal dialog with overlay and proper accessibility',
        path: 'src/components/ui/dialog.tsx',
        template_source: 'shadcn_ui/dialog.tsx'
      },
      'sheet' => {
        description: 'Slide-out panel (drawer) from any edge',
        path: 'src/components/ui/sheet.tsx',
        template_source: 'shadcn_ui/sheet.tsx'
      },
      'toast' => {
        description: 'Notification toast messages',
        path: 'src/components/ui/toast.tsx',
        template_source: 'shadcn_ui/toast.tsx'
      }
    }.freeze
    
    # Form-specific components
    SHADCN_FORM_COMPONENTS = {
      'form' => {
        description: 'React Hook Form integration with validation',
        path: 'src/components/ui/form.tsx',
        template_source: 'shadcn_ui/form.tsx'
      },
      'select' => {
        description: 'Dropdown select with search and custom options',
        path: 'src/components/ui/select.tsx',
        template_source: 'shadcn_ui/select.tsx'
      },
      'combobox' => {
        description: 'Searchable select with autocomplete',
        path: 'src/components/ui/combobox.tsx',
        template_source: 'shadcn_ui/combobox.tsx'
      },
      'date-picker' => {
        description: 'Calendar date picker with range support',
        path: 'src/components/ui/date-picker.tsx',
        template_source: 'shadcn_ui/date-picker.tsx'
      }
    }.freeze
    
    # Data display components
    SHADCN_DATA_COMPONENTS = {
      'table' => {
        description: 'Data table with sorting, filtering, and pagination',
        path: 'src/components/ui/table.tsx',
        template_source: 'shadcn_ui/table.tsx'
      },
      'progress' => {
        description: 'Progress bar with customizable styling',
        path: 'src/components/ui/progress.tsx',
        template_source: 'shadcn_ui/progress.tsx'
      },
      'skeleton' => {
        description: 'Loading skeleton placeholders',
        path: 'src/components/ui/skeleton.tsx',
        template_source: 'shadcn_ui/skeleton.tsx'
      }
    }.freeze
    
    # Navigation components
    SHADCN_NAVIGATION_COMPONENTS = {
      'sidebar' => {
        description: 'Collapsible sidebar with navigation items',
        path: 'src/components/ui/sidebar.tsx',
        template_source: 'shadcn_ui/sidebar.tsx'
      },
      'breadcrumb' => {
        description: 'Navigation breadcrumb trail',
        path: 'src/components/ui/breadcrumb.tsx',
        template_source: 'shadcn_ui/breadcrumb.tsx'
      },
      'navigation-menu' => {
        description: 'Horizontal navigation with dropdowns',
        path: 'src/components/ui/navigation-menu.tsx',
        template_source: 'shadcn_ui/navigation-menu.tsx'
      }
    }.freeze
    
    # Pre-built blocks
    SHADCN_BLOCKS = {
      'login-form-01' => {
        description: 'Professional login form with shadcn/ui components',
        path: 'src/components/blocks/login-form-01.tsx',
        template_source: 'shadcn_blocks/login-01.tsx'
      },
      'dashboard-01' => {
        description: 'Dashboard layout with sidebar and main content',
        path: 'src/components/blocks/dashboard-01.tsx', 
        template_source: 'shadcn_blocks/dashboard-01.tsx'
      },
      'sidebar-01' => {
        description: 'Modern sidebar with collapsible navigation',
        path: 'src/components/blocks/sidebar-01.tsx',
        template_source: 'shadcn_blocks/sidebar-01.tsx'
      }
    }.freeze
    
    def add_category_dependencies(dependencies)
      # This would update package.json with additional dependencies
      # For now, we'll track what needs to be added
      Rails.logger.info "[OptionalComponentService] Dependencies needed: #{dependencies.join(', ')}"
    end
    
    def create_component_file(component_name, component_info, category_key)
      # This would copy the shadcn component template and process it
      template_path = Rails.root.join('app', 'templates', 'optional', component_info[:template_source])
      
      if File.exist?(template_path)
        template_content = ::File.read(template_path)
        processed_content = process_component_template(template_content)
        
        @app.app_files.create!(
          path: component_info[:path],
          content: processed_content,
          team: @app.team
        )
      else
        Rails.logger.warn "[OptionalComponentService] Template not found: #{template_path}"
      end
    end
    
    def process_component_template(content)
      # Process any template variables in component files
      content
        .gsub('{{APP_ID}}', @app.id.to_s)
        .gsub('{{APP_NAME}}', @app.name)
    end
  end
end