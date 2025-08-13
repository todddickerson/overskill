require "test_helper"

class Ai::BaseContextServiceTest < ActiveSupport::TestCase
  def setup
    @team = teams(:one)
    @app = apps(:one)
    @app.update!(team: @team)
    @service = Ai::BaseContextService.new(@app)
  end

  test "builds useful context with essential template files" do
    context = @service.build_useful_context
    
    assert_includes context, "# useful-context"
    assert_includes context, "essential base template files"
    assert_includes context, "DO NOT use os-view to read them again"
    
    # Should include essential files
    assert_includes context, "src/index.css"
    assert_includes context, "tailwind.config.ts"
    assert_includes context, "index.html"
    assert_includes context, "src/App.tsx"
    assert_includes context, "src/pages/Index.tsx"
    
    # Should include common UI components
    assert_includes context, "Common UI Components"
    assert_includes context, "src/components/ui/button.tsx"
    assert_includes context, "src/components/ui/card.tsx"
  end

  test "includes app-specific information when app is provided" do
    @app.update!(
      name: "Test Todo App",
      description: "A test todo application", 
      prompt: "Create a todo app with CRUD operations"
    )
    
    context = @service.build_useful_context
    
    assert_includes context, "App-Specific Information"
    assert_includes context, "**App Name**: Test Todo App"
    assert_includes context, "**Description**: A test todo application"
    assert_includes context, "**User Request**: Create a todo app with CRUD operations"
  end

  test "works without app instance" do
    service = Ai::BaseContextService.new
    context = service.build_useful_context
    
    assert_includes context, "# useful-context"
    assert_includes context, "essential base template files"
    # Should not include app-specific section
    refute_includes context, "App-Specific Information"
  end

  test "builds existing files context for app with files" do
    # Create test app files
    @app.app_files.create!(
      path: "src/components/TodoApp.tsx",
      content: "import React from 'react';\n\nconst TodoApp = () => {\n  return <div>Todo App</div>;\n};\n\nexport default TodoApp;",
      file_type: "jsx",
      team: @team
    )
    
    @app.app_files.create!(
      path: "src/styles/custom.css",
      content: ".todo-item {\n  padding: 10px;\n  margin: 5px;\n}",
      file_type: "css",
      team: @team
    )
    
    context = @service.build_existing_files_context(@app)
    
    assert_includes context, "Existing App Files"
    assert_includes context, "src/components/TodoApp.tsx"
    assert_includes context, "src/styles/custom.css"
    assert_includes context, "import React from 'react';"
    assert_includes context, ".todo-item {"
  end

  test "returns empty string for app without files" do
    context = @service.build_existing_files_context(@app)
    
    assert_equal "", context
  end

  test "returns empty string for nil app" do
    context = @service.build_existing_files_context(nil)
    
    assert_equal "", context
  end

  test "groups existing files by directory" do
    # Create files in different directories
    @app.app_files.create!(
      path: "src/components/Header.tsx",
      content: "export const Header = () => <h1>Header</h1>;",
      file_type: "tsx",
      team: @team
    )
    
    @app.app_files.create!(
      path: "src/utils/helpers.ts",
      content: "export const formatDate = (date: Date) => date.toISOString();",
      file_type: "ts", 
      team: @team
    )
    
    @app.app_files.create!(
      path: "package.json",
      content: '{"name": "test-app", "version": "1.0.0"}',
      file_type: "json",
      team: @team
    )
    
    context = @service.build_existing_files_context(@app)
    
    # Should have directory sections
    assert_includes context, "### src/components/"
    assert_includes context, "### src/utils/"
    assert_includes context, "### Root/"
    
    # Files should be under correct directories
    assert_match(/### src\/components\/.*Header\.tsx/m, context)
    assert_match(/### src\/utils\/.*helpers\.ts/m, context)
    assert_match(/### Root\/.*package\.json/m, context)
  end

  test "handles missing template files gracefully" do
    # Mock the template path to point to non-existent directory
    original_path = Ai::BaseContextService::TEMPLATE_PATH
    Ai::BaseContextService.const_set(:TEMPLATE_PATH, Rails.root.join("nonexistent"))
    
    # Should not raise error
    assert_nothing_raised do
      context = @service.build_useful_context
      assert_includes context, "# useful-context"
    end
    
    # Restore original path
    Ai::BaseContextService.const_set(:TEMPLATE_PATH, original_path)
  end

  test "detects correct file extensions for syntax highlighting" do
    # Test file extension detection
    service = Ai::BaseContextService.new
    
    assert_equal "typescript", service.send(:get_file_extension, "src/App.tsx")
    assert_equal "typescript", service.send(:get_file_extension, "utils/helper.ts")
    assert_equal "javascript", service.send(:get_file_extension, "src/legacy.jsx")
    assert_equal "javascript", service.send(:get_file_extension, "scripts/build.js")
    assert_equal "css", service.send(:get_file_extension, "styles/main.css")
    assert_equal "html", service.send(:get_file_extension, "public/index.html")
    assert_equal "json", service.send(:get_file_extension, "package.json")
    assert_equal "text", service.send(:get_file_extension, "README.md")
  end

  test "limits app information display when no optional fields present" do
    @app.update!(description: nil, prompt: nil)
    
    context = @service.build_useful_context
    
    assert_includes context, "**App Name**: #{@app.name}"
    refute_includes context, "**Description**:"
    refute_includes context, "**User Request**:"
  end

  test "shows recent files information when app has files" do
    # Create multiple files with different timestamps
    5.times do |i|
      @app.app_files.create!(
        path: "src/component#{i}.tsx",
        content: "export const Component#{i} = () => <div>Component #{i}</div>;",
        file_type: "tsx",
        team: @team,
        created_at: i.hours.ago,
        updated_at: i.hours.ago
      )
    end
    
    context = @service.build_useful_context
    
    assert_includes context, "**Existing Files**: 5 files already created"
    assert_includes context, "Most recent files:"
    
    # Should show most recent files first (component0 was created most recently)
    assert_includes context, "- src/component0.tsx (tsx)"
  end

  private

  def assert_includes_code_block(context, file_path, language = nil)
    language ||= case File.extname(file_path)
                 when '.tsx', '.ts' then 'typescript'
                 when '.jsx', '.js' then 'javascript'
                 when '.css' then 'css'
                 when '.html' then 'html'
                 when '.json' then 'json'
                 else 'text'
                 end
    
    assert_includes context, "## Essential: #{file_path}"
    assert_includes context, "```#{language}"
  end
end