require "test_helper"

class Ai::AppBuilderV4WithComponentsTest < ActiveSupport::TestCase
  setup do
    # Create test data with unique email and strong password
    timestamp = Time.now.to_i
    @user = User.create!(
      email: "test_v4_components_#{timestamp}@example.com",
      password: "SecureP@ssw0rd!2024"
    )
    @team = Team.create!(name: "Test Team #{timestamp}")
    @membership = @team.memberships.create!(user: @user, role_ids: ["admin"])

    @app = App.create!(
      name: "Chat Application",
      subdomain: "chat-app",
      team: @team,
      creator: @membership,
      prompt: "Build a realtime chat application",
      status: "pending"
    )

    @message = AppChatMessage.create!(
      app: @app,
      user: @user,
      role: "user",
      content: "Build a realtime chat application with authentication and file uploads"
    )
  end

  test "shared template service generates foundation files" do
    template_service = Ai::SharedTemplateService.new(@app)
    files_created = template_service.generate_core_files

    # Verify foundation files were created
    assert @app.app_files.exists?(path: "package.json")
    assert @app.app_files.exists?(path: "src/main.tsx")
    assert @app.app_files.exists?(path: "src/lib/supabase.ts")
    assert @app.app_files.exists?(path: "src/lib/app-scoped-db.ts")
    assert @app.app_files.exists?(path: "src/App.tsx")
    assert @app.app_files.exists?(path: "src/hooks/useAuth.ts")

    # Verify file count
    assert files_created.size > 10, "Should create multiple foundation files"
  end

  test "enhanced component service detects auth components" do
    service = Ai::EnhancedOptionalComponentService.new(@app)

    # Test auth detection
    components = service.detect_and_add_components("Build a login system with password authentication")
    assert_includes components, "supabase_ui_auth"

    # Verify files created
    assert @app.app_files.exists?(path: "src/components/auth/password-based-auth.tsx")
  end

  test "enhanced component service detects realtime components" do
    service = Ai::EnhancedOptionalComponentService.new(@app)

    # Test realtime detection
    components = service.detect_and_add_components("Add realtime chat functionality")
    assert_includes components, "supabase_ui_realtime"

    # Verify files created
    assert @app.app_files.exists?(path: "src/components/realtime/realtime-chat.tsx")
  end

  test "enhanced component service detects file upload components" do
    service = Ai::EnhancedOptionalComponentService.new(@app)

    # Test upload detection
    components = service.detect_and_add_components("Users should be able to upload files and attachments")
    assert_includes components, "supabase_ui_data"

    # Verify files created
    assert @app.app_files.exists?(path: "src/components/data/dropzone.tsx")
  end

  test "generates AI context with Supabase UI components" do
    service = Ai::EnhancedOptionalComponentService.new(@app)
    context = service.generate_ai_context_with_supabase

    # Verify context includes Supabase UI components
    assert_match(/Supabase Auth Components/, context)
    assert_match(/Password-Based Auth/, context)
    assert_match(/Social Auth/, context)
    assert_match(/Realtime Chat/, context)
    assert_match(/Dropzone/, context)
    assert_match(/shadcn\/ui Components/, context)
  end

  test "updates package.json with component dependencies" do
    # Create initial package.json
    @app.app_files.create!(
      path: "package.json",
      content: JSON.pretty_generate({
        name: "test-app",
        dependencies: {
          react: "^18.2.0"
        }
      }),
      team: @team
    )

    builder = Ai::AppBuilderV4.new(@message)

    # Add new dependencies
    builder.send(:update_package_json_dependencies, [
      "@supabase/auth-helpers-react",
      "react-dropzone",
      "@radix-ui/react-dialog"
    ])

    # Verify package.json was updated
    package_file = @app.app_files.find_by(path: "package.json")
    package_json = JSON.parse(package_file.content)

    assert package_json["dependencies"]["@supabase/auth-helpers-react"]
    assert package_json["dependencies"]["react-dropzone"]
    assert package_json["dependencies"]["@radix-ui/react-dialog"]
    assert package_json["dependencies"]["react"] # Original dependency preserved
  end

  test "get required dependencies based on added components" do
    # Add component files
    @app.app_files.create!(
      path: "src/components/auth/password-based-auth.tsx",
      content: "export function PasswordBasedAuth() {}",
      team: @team
    )
    @app.app_files.create!(
      path: "src/components/data/dropzone.tsx",
      content: "export function Dropzone() {}",
      team: @team
    )
    @app.app_files.create!(
      path: "src/components/ui/button.tsx",
      content: "export function Button() {}",
      team: @team
    )

    service = Ai::EnhancedOptionalComponentService.new(@app)
    dependencies = service.get_required_dependencies

    assert_includes dependencies, "@supabase/auth-helpers-react"
    assert_includes dependencies, "react-dropzone"
    assert_includes dependencies, "@radix-ui/react-dialog"
    assert_includes dependencies, "class-variance-authority"
  end

  test "component detection is case insensitive" do
    service = Ai::EnhancedOptionalComponentService.new(@app)

    # Test various case combinations
    components = service.detect_and_add_components("Add LOGIN and AUTHENTICATION with FILE UPLOAD")

    assert_includes components, "supabase_ui_auth"
    assert_includes components, "supabase_ui_data"
  end

  test "handles multiple component categories in single request" do
    Ai::AppBuilderV4.new(@message)

    # Message with multiple component needs
    @message.update!(content: "Build an app with authentication, realtime chat, file uploads, and admin dashboard")

    service = Ai::EnhancedOptionalComponentService.new(@app)
    components = service.detect_and_add_components(@message.content)

    # Should detect multiple categories
    assert components.size >= 3
    assert_includes components, "supabase_ui_auth"
    assert_includes components, "supabase_ui_realtime"
    assert_includes components, "supabase_ui_data"
  end
end
