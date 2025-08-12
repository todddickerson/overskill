module Ai
  class EnhancedOptionalComponentService
    def initialize(app)
      @app = app
    end
    
    # Get available component categories including Supabase UI
    def available_component_categories
      {
        'shadcn_ui_core' => {
          description: 'Core shadcn/ui components with variants and TypeScript',
          components: SHADCN_CORE_COMPONENTS,
          dependencies: ['@radix-ui/react-dialog', '@radix-ui/react-slot', 'class-variance-authority', 'lucide-react']
        },
        'shadcn_ui_forms' => {
          description: 'Advanced form components with validation',
          components: SHADCN_FORM_COMPONENTS,
          dependencies: ['@hookform/resolvers', 'react-hook-form', 'zod', '@radix-ui/react-popover']
        },
        'supabase_ui_auth' => {
          description: 'Complete Supabase authentication system with email verification',
          components: SUPABASE_AUTH_COMPONENTS,
          dependencies: ['@supabase/auth-helpers-nextjs', '@supabase/auth-helpers-react']
        },
        'supabase_ui_data' => {
          description: 'Advanced data handling and file management',
          components: SUPABASE_DATA_COMPONENTS,
          dependencies: ['react-dropzone', '@tanstack/react-query', 'react-intersection-observer']
        },
        'supabase_ui_realtime' => {
          description: 'Real-time collaboration features',
          components: SUPABASE_REALTIME_COMPONENTS,
          dependencies: ['@supabase/realtime-js']
        },
        'supabase_ui_platform' => {
          description: 'Full database management interface',
          components: SUPABASE_PLATFORM_COMPONENTS,
          dependencies: ['@monaco-editor/react', 'recharts', '@supabase/postgres-meta']
        }
      }
    end
    
    # Generate enhanced AI context with Supabase UI awareness
    def generate_ai_context_with_supabase
      context = []
      context << "## Professional Component Libraries Available"
      context << ""
      context << "You have access to high-quality, production-ready components:"
      context << ""
      
      # shadcn/ui components
      context << "### 🎨 shadcn/ui Components"
      context << "Modern, accessible UI components with variants and proper TypeScript"
      context << "- **Button**: 6 variants (default, destructive, outline, secondary, ghost, link)"
      context << "- **Card**: Container with header, content, footer sections"
      context << "- **Input**: Styled input fields with proper focus states"
      context << "- **Dialog**: Modal dialogs with overlay and accessibility"
      context << "- **Sheet**: Slide-out panels (drawers) from any edge"
      context << "- **Form**: React Hook Form integration with validation"
      context << "- **Select**: Dropdown selects with search capabilities"
      context << ""
      
      # Supabase UI components
      context << "### 🔐 Supabase Auth Components"
      context << "Production-ready authentication with complete flows"
      context << "- **Password-Based Auth**: Complete login/signup/forgot-password flow"
      context << "- **Social Auth**: OAuth with GitHub, Google, and other providers"
      context << "- **Current User Avatar**: Automatic avatar with user metadata"
      context << "- **Protected Routes**: Authentication guards and middleware"
      context << ""
      
      context << "### 📊 Supabase Data Components"
      context << "Advanced data handling and file management"
      context << "- **Infinite Query Hook**: Pagination and progressive loading"
      context << "- **Dropzone**: Drag-and-drop file upload to Supabase Storage"
      context << "- **Results Table**: Display query results with sorting/filtering"
      context << ""
      
      context << "### ⚡ Supabase Realtime Components"
      context << "Real-time collaboration features"
      context << "- **Realtime Chat**: Multi-user chat system with persistence"
      context << "- **Realtime Cursor**: Shared cursor tracking for collaboration"
      context << "- **Realtime Avatar Stack**: Show online users in real-time"
      context << ""
      
      context << "### 🛠️ Supabase Platform Components"
      context << "Database management and analytics interface"
      context << "- **Platform Kit**: Complete embedded database manager"
      context << "- **SQL Editor**: AI-powered SQL query interface"
      context << "- **Users Growth Chart**: Analytics and user growth visualization"
      context << ""
      
      context << "## Component Usage Examples:"
      context << ""
      context << "**For modern UI:**"
      context << "- 'Use shadcn/ui Button components instead of basic HTML buttons'"
      context << "- 'Add Card components to organize content professionally'"
      context << "- 'Include Dialog components for modals and confirmations'"
      context << ""
      context << "**For authentication:**"
      context << "- 'Add Supabase password-based auth for complete login system'"
      context << "- 'Include social auth for GitHub/Google login options'"
      context << "- 'Use current user avatar component in the header'"
      context << ""
      context << "**For data and collaboration:**"
      context << "- 'Add infinite query hook for paginated data loading'"
      context << "- 'Include dropzone for file uploads to Supabase Storage'"
      context << "- 'Add realtime chat for user collaboration'"
      context << ""
      context << "**To request components:**"
      context << "Say things like: 'Add shadcn/ui core components' or 'Include Supabase auth components'"
      context << ""
      
      context.join("\n")
    end
    
    # Add specific component category to the app
    def add_component_category(category_key)
      category = available_component_categories[category_key]
      return false unless category
      
      Rails.logger.info "[EnhancedOptionalComponentService] Adding #{category_key} components to app ##{@app.id}"
      
      # Add dependencies to package.json if needed
      add_category_dependencies(category[:dependencies]) if category[:dependencies].any?
      
      # Add component files
      category[:components].each do |component_name, component_info|
        create_component_file(component_name, component_info, category_key)
      end
      
      Rails.logger.info "[EnhancedOptionalComponentService] Added #{category[:components].size} components from #{category_key}"
      true
    end
    
    private
    
    # Core shadcn/ui components
    SHADCN_CORE_COMPONENTS = {
      'button' => {
        description: 'Flexible button with 6 variants and size options',
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
        description: 'Modal dialog with overlay and accessibility',
        path: 'src/components/ui/dialog.tsx',
        template_source: 'shadcn_ui/dialog.tsx'
      },
      'sheet' => {
        description: 'Slide-out panel (drawer) from any edge',
        path: 'src/components/ui/sheet.tsx',
        template_source: 'shadcn_ui/sheet.tsx'
      }
    }.freeze
    
    # Form components
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
      'label' => {
        description: 'Form label with proper accessibility',
        path: 'src/components/ui/label.tsx',
        template_source: 'shadcn_ui/label.tsx'
      }
    }.freeze
    
    # Supabase authentication components
    SUPABASE_AUTH_COMPONENTS = {
      'password-based-auth' => {
        description: 'Complete authentication flow with signup, login, forgot password',
        path: 'src/components/auth/password-based-auth.tsx',
        template_source: 'supabase_ui/auth/password-based-auth.tsx'
      },
      'social-auth' => {
        description: 'OAuth authentication with multiple providers',
        path: 'src/components/auth/social-auth.tsx',
        template_source: 'supabase_ui/auth/social-auth.tsx'
      },
      'current-user-avatar' => {
        description: 'Auth-aware avatar with automatic user metadata',
        path: 'src/components/auth/current-user-avatar.tsx',
        template_source: 'supabase_ui/auth/current-user-avatar.tsx'
      }
    }.freeze
    
    # Supabase data components
    SUPABASE_DATA_COMPONENTS = {
      'infinite-query-hook' => {
        description: 'React hook for infinite lists and pagination',
        path: 'src/hooks/use-infinite-query.ts',
        template_source: 'supabase_ui/data/infinite-query-hook.ts'
      },
      'dropzone' => {
        description: 'Drag-and-drop file upload to Supabase Storage',
        path: 'src/components/data/dropzone.tsx',
        template_source: 'supabase_ui/data/dropzone.tsx'
      }
    }.freeze
    
    # Supabase realtime components
    SUPABASE_REALTIME_COMPONENTS = {
      'realtime-chat' => {
        description: 'Real-time chat system with persistence support',
        path: 'src/components/realtime/realtime-chat.tsx',
        template_source: 'supabase_ui/realtime/realtime-chat.tsx'
      },
      'realtime-cursor' => {
        description: 'Shared cursor tracking for collaboration',
        path: 'src/components/realtime/realtime-cursor.tsx',
        template_source: 'supabase_ui/realtime/realtime-cursor.tsx'
      },
      'realtime-avatar-stack' => {
        description: 'Show online users in real-time',
        path: 'src/components/realtime/realtime-avatar-stack.tsx',
        template_source: 'supabase_ui/realtime/realtime-avatar-stack.tsx'
      }
    }.freeze
    
    # Supabase platform components
    SUPABASE_PLATFORM_COMPONENTS = {
      'platform-kit' => {
        description: 'Complete embedded database management interface',
        path: 'src/components/platform/platform-kit.tsx',
        template_source: 'supabase_ui/platform/platform-kit.tsx'
      },
      'sql-editor' => {
        description: 'AI-powered SQL query interface',
        path: 'src/components/platform/sql-editor.tsx',
        template_source: 'supabase_ui/platform/sql-editor.tsx'
      }
    }.freeze
    
    def add_category_dependencies(dependencies)
      # This would update package.json with additional dependencies
      Rails.logger.info "[EnhancedOptionalComponentService] Dependencies needed: #{dependencies.join(', ')}"
      
      # TODO: Implement package.json updates in future iteration
      # For now, we'll track what needs to be added
    end
    
    def create_component_file(component_name, component_info, category_key)
      template_path = Rails.root.join('app', 'templates', 'optional', component_info[:template_source])
      
      if ::File.exist?(template_path)
        template_content = ::File.read(template_path)
        processed_content = process_component_template(template_content)
        
        @app.app_files.create!(
          path: component_info[:path],
          content: processed_content,
          team: @app.team
        )
        
        Rails.logger.info "[EnhancedOptionalComponentService] Created #{component_info[:path]}"
      else
        Rails.logger.warn "[EnhancedOptionalComponentService] Template not found: #{template_path}"
        
        # Create placeholder for missing templates
        create_placeholder_component(component_name, component_info)
      end
    end
    
    def create_placeholder_component(component_name, component_info)
      placeholder_content = generate_placeholder_content(component_name, component_info)
      
      @app.app_files.create!(
        path: component_info[:path],
        content: placeholder_content,
        team: @app.team
      )
      
      Rails.logger.info "[EnhancedOptionalComponentService] Created placeholder for #{component_info[:path]}"
    end
    
    def generate_placeholder_content(component_name, component_info)
      <<~TYPESCRIPT
        // #{component_name.humanize} Component
        // #{component_info[:description]}
        // TODO: Implement full component from Supabase UI
        
        import React from 'react';
        
        export default function #{component_name.classify}() {
          return (
            <div className="p-4 border rounded-md">
              <h3 className="font-medium">#{component_name.humanize}</h3>
              <p className="text-sm text-gray-600 mt-1">
                #{component_info[:description]}
              </p>
              <p className="text-xs text-orange-600 mt-2">
                ⚠️ This is a placeholder. Full component implementation needed.
              </p>
            </div>
          );
        }
      TYPESCRIPT
    end
    
    def process_component_template(content)
      # Process template variables
      content
        .gsub('{{APP_ID}}', @app.id.to_s)
        .gsub('{{APP_NAME}}', @app.name)
        .gsub('{{APP_SLUG}}', @app.slug)
    end
    
    public
    
    # Detect which components to add based on AI response
    def detect_and_add_components(ai_response_text)
      components_added = []
      
      # Check for authentication components
      if ai_response_text.match?(/\b(auth|login|signup|sign.?up|sign.?in|password|authentication)\b/i)
        add_component_category('supabase_ui_auth')
        components_added << 'supabase_ui_auth' unless components_added.include?('supabase_ui_auth')
      end
      
      # Check for file upload
      if ai_response_text.match?(/\b(upload|dropzone|file|storage|attachment)\b/i)
        add_component_category('supabase_ui_data')
        components_added << 'supabase_ui_data'
      end
      
      # Check for realtime features
      if ai_response_text.match?(/\b(realtime|chat|cursor|presence|collaboration)\b/i)
        add_component_category('supabase_ui_realtime')
        components_added << 'supabase_ui_realtime'
      end
      
      # Check for UI components
      if ai_response_text.match?(/\b(button|card|dialog|form|input)\b/i)
        add_component_category('shadcn_ui_core')
        components_added << 'shadcn_ui_core'
      end
      
      # Check for database management
      if ai_response_text.match?(/\b(database|sql|query|platform)\b/i)
        if ai_response_text.match?(/\b(management|admin|platform)\b/i)
          add_component_category('supabase_ui_platform')
          components_added << 'supabase_ui_platform'
        end
      end
      
      Rails.logger.info "[EnhancedOptionalComponentService] Detected and added components: #{components_added.join(', ')}" if components_added.any?
      components_added
    end
    
    # Get list of dependencies needed for added components
    def get_required_dependencies
      dependencies = Set.new
      
      # Check which categories have been added by looking at files
      @app.app_files.pluck(:path).each do |path|
        # Supabase auth components
        if path.include?('components/auth/password-based-auth')
          dependencies.add('@supabase/auth-helpers-react')
        end
        
        # Dropzone
        if path.include?('components/data/dropzone')
          dependencies.add('react-dropzone')
        end
        
        # Realtime components
        if path.include?('components/realtime/')
          dependencies.add('@supabase/realtime-js')
        end
        
        # shadcn/ui components
        if path.include?('components/ui/')
          dependencies.add('@radix-ui/react-dialog')
          dependencies.add('@radix-ui/react-slot')
          dependencies.add('class-variance-authority')
          dependencies.add('lucide-react')
        end
        
        # Platform kit
        if path.include?('components/platform/')
          dependencies.add('@monaco-editor/react')
          dependencies.add('recharts')
        end
      end
      
      dependencies.to_a
    end
  end
end