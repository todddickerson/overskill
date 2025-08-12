require 'test_helper'

class Ai::SharedTemplateServiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @team = teams(:one)
    @app = apps(:one)
    @service = Ai::SharedTemplateService.new(@app)
  end

  test "initializes with correct template paths" do
    assert_equal @app, @service.instance_variable_get(:@app)
    assert_not_nil @service.instance_variable_get(:@template_base_path)
  end

  test "generates all core template categories" do
    # Mock file creation
    created_files = []
    
    AppFile.stub :create!, ->(attrs) { 
      created_files << attrs
      AppFile.new(attrs) 
    } do
      @service.generate_core_files
    end

    # Verify all categories are represented
    paths = created_files.map { |f| f[:path] }
    
    # Auth templates
    assert paths.any? { |p| p.include?('auth/login.tsx') }
    assert paths.any? { |p| p.include?('auth/signup.tsx') }
    assert paths.any? { |p| p.include?('auth/protected-route.tsx') }
    
    # Database templates  
    assert paths.any? { |p| p.include?('lib/supabase-client.ts') }
    assert paths.any? { |p| p.include?('lib/app-scoped-db.ts') }
    
    # Routing templates
    assert paths.any? { |p| p.include?('app-router.tsx') }
    assert paths.any? { |p| p.include?('navigation.tsx') }
    
    # Core config templates
    assert paths.any? { |p| p.include?('package.json') }
    assert paths.any? { |p| p.include?('vite.config.ts') }
    assert paths.any? { |p| p.include?('tailwind.config.js') }
  end

  test "generates exactly 17 template files" do
    created_count = 0
    
    AppFile.stub :create!, ->(attrs) { 
      created_count += 1
      AppFile.new(attrs) 
    } do
      @service.generate_core_files
    end

    assert_equal 17, created_count, "Should generate exactly 17 template files"
  end

  test "processes template variables correctly" do
    template_content = "Welcome to {{APP_NAME}} (ID: {{APP_ID}})"
    
    processed = @service.send(:process_template_variables, template_content)
    
    assert_includes processed, @app.name
    assert_includes processed, @app.id.to_s
    assert_not_includes processed, "{{APP_NAME}}"
    assert_not_includes processed, "{{APP_ID}}"
  end

  test "determines correct target paths" do
    # Auth file
    auth_path = @service.send(:determine_target_path, 'auth/login.tsx')
    assert_equal 'src/pages/auth/login.tsx', auth_path
    
    # Database file
    db_path = @service.send(:determine_target_path, 'database/supabase-client.ts')
    assert_equal 'src/lib/supabase-client.ts', db_path
    
    # Routing file
    route_path = @service.send(:determine_target_path, 'routing/app-router.tsx')
    assert_equal 'src/app-router.tsx', route_path
    
    # Core file (root level)
    core_path = @service.send(:determine_target_path, 'core/package.json')
    assert_equal 'package.json', core_path
  end

  test "loads template content from file system" do
    # Test with a template that should exist
    template_path = 'core/package.json'
    
    content = @service.send(:load_template_content, template_path)
    
    assert_not_nil content
    assert content.is_a?(String)
    assert_includes content, '"name"'
    assert_includes content, '"dependencies"'
  end

  test "handles missing template files gracefully" do
    template_path = 'nonexistent/template.tsx'
    
    content = @service.send(:load_template_content, template_path)
    
    assert_includes content, "Template not found"
    assert_includes content, template_path
  end

  test "creates app files with correct attributes" do
    file_created = nil
    
    AppFile.stub :create!, ->(attrs) { 
      file_created = attrs
      AppFile.new(attrs) 
    } do
      @service.send(:create_app_file, 'test.tsx', 'test content')
    end

    assert_equal @app, file_created[:app]
    assert_equal @team, file_created[:team]
    assert_equal 'test.tsx', file_created[:path]
    assert_equal 'test content', file_created[:content]
  end

  test "generates auth templates with shadcn UI fallbacks" do
    created_files = []
    
    AppFile.stub :create!, ->(attrs) { 
      created_files << attrs
      AppFile.new(attrs) 
    } do
      @service.generate_core_files
    end

    # Find login template
    login_file = created_files.find { |f| f[:path].include?('login.tsx') }
    assert_not_nil login_file
    
    # Check for shadcn/ui component imports with fallbacks
    assert_includes login_file[:content], '@/components/ui/button'
    assert_includes login_file[:content], 'fallback to basic HTML'
  end

  test "generates app-scoped database wrapper" do
    created_files = []
    
    AppFile.stub :create!, ->(attrs) { 
      created_files << attrs
      AppFile.new(attrs) 
    } do
      @service.generate_core_files
    end

    # Find app-scoped-db template
    db_file = created_files.find { |f| f[:path].include?('app-scoped-db.ts') }
    assert_not_nil db_file
    
    # Check for critical multi-tenant functionality
    assert_includes db_file[:content], 'app_${this.appId}_${table}'
    assert_includes db_file[:content], 'getTableName'
    assert_includes db_file[:content], 'AppScopedDatabase'
  end

  test "logs progress during generation" do
    logs = []
    
    Rails.logger.stub :info, ->(msg) { logs << msg } do
      @service.generate_core_files
    end
    
    assert logs.any? { |log| log.include?('Generating shared foundation') }
    assert logs.any? { |log| log.include?('Generated 17 core files') }
  end

  test "all template files have unique paths" do
    created_files = []
    
    AppFile.stub :create!, ->(attrs) { 
      created_files << attrs
      AppFile.new(attrs) 
    } do
      @service.generate_core_files
    end

    paths = created_files.map { |f| f[:path] }
    assert_equal paths.uniq.size, paths.size, "All template paths should be unique"
  end
end