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

  test "requires slug" do
    app = build(:app, slug: nil)
    assert_not app.valid?
    assert_includes app.errors[:slug], "can't be blank"
  end

  test "slug must be unique" do
    create(:app, slug: "test-app", team: @team, creator: @membership)
    duplicate = build(:app, slug: "test-app", team: @team, creator: @membership)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:slug], "has already been taken"
  end

  test "generates slug before validation if blank" do
    app = build(:app, name: "My Cool App", slug: nil, team: @team, creator: @membership)
    app.valid?
    assert_equal "my-cool-app", app.slug
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
end
