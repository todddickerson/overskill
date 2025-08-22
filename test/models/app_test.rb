require "test_helper"

class AppTest < ActiveSupport::TestCase
  setup do
    @team = create(:team)
    @membership = create(:membership, team: @team)
  end

  test "valid app" do
    app = build(:app, team: @team, creator: @membership)
    assert app.valid?
  end

  test "requires name" do
    app = build(:app, name: nil)
    assert_not app.valid?
    assert_includes app.errors[:name], "can't be blank"
  end

  test "generates subdomain if blank" do
    app = build(:app, name: "My Cool App", subdomain: nil)
    assert app.valid?
    assert_equal "my-cool-app", app.subdomain
  end

  test "subdomain must be unique" do
    create(:app, subdomain: "test-app", team: @team, creator: @membership)
    duplicate = build(:app, subdomain: "test-app", team: @team, creator: @membership)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:subdomain], "has already been taken"
  end

  test "generates subdomain before validation if blank" do
    app = build(:app, name: "My Cool App", subdomain: nil, team: @team, creator: @membership)
    app.valid?
    assert_equal "my-cool-app", app.subdomain
  end

  test "has many app_files" do
    app = create(:app, team: @team, creator: @membership)
    assert_respond_to app, :app_files
  end

  test "has many app_versions" do
    app = create(:app, team: @team, creator: @membership)
    assert_respond_to app, :app_versions
  end

  test "has many app_chat_messages" do
    app = create(:app, team: @team, creator: @membership)
    assert_respond_to app, :app_chat_messages
  end

  test "generated? returns true when status is generated" do
    app = build(:app, status: "generated")
    assert app.generated?
  end

  test "generating? returns true when status is generating" do
    app = build(:app, status: "generating")
    assert app.generating?
  end

  test "published scope returns only published apps" do
    create(:app, :published, team: @team, creator: @membership)
    create(:app, status: "draft", team: @team, creator: @membership)

    published_apps = App.published
    assert_equal 1, published_apps.count
    assert_equal "published", published_apps.first.status
  end

  test "featured scope returns only featured apps with valid date" do
    create(:app, :featured, team: @team, creator: @membership)
    create(:app, featured: true, featured_until: 1.day.ago, team: @team, creator: @membership)
    create(:app, featured: false, team: @team, creator: @membership)

    featured_apps = App.featured
    assert_equal 1, featured_apps.count
    assert featured_apps.first.featured?
    assert featured_apps.first.featured_until > Time.current
  end

  # Golden Flow Testing - Rails 8 + Bullet Train Integration

  test "should support end-to-end app generation golden flow" do
    # Test the complete app generation lifecycle
    app = create(:app, 
      name: "Test Todo App",
      prompt: "Create a simple todo app with add, edit, delete functionality", 
      status: "pending",
      team: @team, 
      creator: @membership
    )

    assert_equal "pending", app.status
    assert_not app.generated?

    # Simulate AI generation process
    app.update!(status: "generating")
    assert app.generating?

    # Create files as AI would (matches golden flow expectations)
    app.app_files.create!([
      { path: "index.html", content: "<h1>Todo App</h1>", team: @team },
      { path: "app.js", content: "console.log('todo app');", team: @team },
      { path: "style.css", content: "body { font-family: Arial; }", team: @team }
    ])

    # Complete generation
    app.update!(status: "generated")
    assert app.generated?
    assert_equal 3, app.app_files.count

    # Verify golden flow file structure
    file_paths = app.app_files.pluck(:path)
    assert_includes file_paths, "index.html"
    assert file_paths.any? { |path| path.include?(".js") }
    assert file_paths.any? { |path| path.include?(".css") }
  end

  test "should support end-to-end publishing golden flow" do
    # Create generated app ready for publishing
    app = create(:app, 
      status: "generated",
      team: @team, 
      creator: @membership
    )

    # Add generated files
    app.app_files.create!([
      { path: "index.html", content: "<h1>Test App</h1>", team: @team },
      { path: "app.js", content: "console.log('test');", team: @team },
      { path: "style.css", content: "body { margin: 0; }", team: @team }
    ])

    assert app.generated?

    # Simulate publishing workflow
    production_url = "https://app-#{app.id}.overskill.app"
    app.update!(
      status: "published",
      production_url: production_url,
      published_at: Time.current
    )

    assert app.published?
    assert_not_nil app.production_url
    assert app.production_url.include?("overskill.app")
    assert_not_nil app.published_at
  end

  test "should track golden flow performance metrics" do
    start_time = Time.current

    # Simulate app creation timing
    app = create(:app, team: @team, creator: @membership)
    
    creation_duration = Time.current - start_time
    
    # Golden flow baseline: app creation should be fast
    assert creation_duration < 1.0, "App creation took #{creation_duration}s, should be < 1.0s"

    # Simulate file creation timing (AI generation simulation)
    file_creation_start = Time.current
    
    app.app_files.create!([
      { path: "index.html", content: "<h1>Test</h1>" * 100, team: @team },
      { path: "app.js", content: "console.log('test');" * 50, team: @team },
      { path: "style.css", content: "body { margin: 0; }" * 20, team: @team }
    ])

    file_creation_duration = Time.current - file_creation_start

    # File creation should be reasonable for golden flow testing
    assert file_creation_duration < 2.0, "File creation took #{file_creation_duration}s, should be < 2.0s"
  end

  test "should validate app data for authentication golden flow" do
    # Test that apps are properly associated with users for auth testing
    app = create(:app, team: @team, creator: @membership)

    assert_equal @team, app.team
    assert_equal @membership, app.creator
    assert_equal @membership.user, app.creator.user

    # Verify user can access their apps (auth golden flow requirement)
    user_apps = App.joins(:creator).where(memberships: { user: @membership.user })
    assert_includes user_apps, app
  end

  test "should handle app status transitions for golden flow testing" do
    app = create(:app, status: "pending", team: @team, creator: @membership)

    # Test valid status transitions used in golden flows
    valid_transitions = %w[pending generating generated published failed]
    
    valid_transitions.each do |status|
      app.update!(status: status)
      assert_equal status, app.status
      
      # Test status query methods
      case status
      when "generating"
        assert app.generating?
      when "generated"  
        assert app.generated?
      when "published"
        assert app.published?
      end
    end
  end

  test "should validate required attributes for golden flow creation" do
    # Test minimum required data for golden flow app creation
    app = build(:app, 
      name: nil,
      prompt: nil, 
      team: @team,
      creator: @membership
    )

    assert_not app.valid?
    assert_includes app.errors[:name], "can't be blank"
    # Note: prompt validation may be handled elsewhere in the app
  end
end
