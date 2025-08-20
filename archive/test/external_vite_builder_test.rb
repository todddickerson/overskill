require 'test_helper'

class Deployment::ExternalViteBuilderTest < ActiveSupport::TestCase
  setup do
    @team = Team.create!(name: 'Test Team')
    @user = User.create!(email: 'test@example.com', password: 'password123')
    @membership = @team.memberships.create!(user: @user, role_ids: ['admin'])
    @app = App.create!(
      name: 'Test App',
      team: @team,
      creator: @membership,
      prompt: 'Test prompt'
    )
    
    # Create some test files for the app
    @app.app_files.create!(
      path: 'package.json',
      content: '{"name": "test-app", "scripts": {}}',
      team: @team
    )
    
    @app.app_files.create!(
      path: 'src/App.tsx',
      content: 'export default function App() { return <div>Test</div> }',
      team: @team
    )
    
    @builder = Deployment::ExternalViteBuilder.new(@app)
  end
  
  test "initializes with app" do
    assert_equal @app, @builder.instance_variable_get(:@app)
  end
  
  test "creates temp directory for build" do
    temp_dir = @builder.send(:create_temp_directory)
    
    assert Dir.exist?(temp_dir)
    assert temp_dir.to_s.include?("app_#{@app.id}")
    
    # Cleanup
    FileUtils.rm_rf(temp_dir) if Dir.exist?(temp_dir)
  end
  
  test "writes app files to disk" do
    temp_dir = @builder.send(:create_temp_directory)
    @builder.instance_variable_set(:@temp_dir, temp_dir)
    
    @builder.send(:write_app_files_to_disk)
    
    # Check files were written
    assert File.exist?(temp_dir.join('package.json'))
    assert File.exist?(temp_dir.join('src/App.tsx'))
    
    # Check content matches
    package_content = File.read(temp_dir.join('package.json'))
    assert_includes package_content, '"name"'
    
    # Cleanup
    FileUtils.rm_rf(temp_dir) if Dir.exist?(temp_dir)
  end
  
  test "ensures build scripts in package.json" do
    temp_dir = @builder.send(:create_temp_directory)
    @builder.instance_variable_set(:@temp_dir, temp_dir)
    
    # Write initial package.json
    File.write(temp_dir.join('package.json'), '{"name": "test"}')
    
    @builder.send(:ensure_build_scripts)
    
    package_json = JSON.parse(File.read(temp_dir.join('package.json')))
    
    assert package_json['scripts']['build']
    assert_equal 'vite build', package_json['scripts']['build']
    assert_equal 'vite build --mode development', package_json['scripts']['build:preview']
    
    # Cleanup
    FileUtils.rm_rf(temp_dir) if Dir.exist?(temp_dir)
  end
  
  test "creates minimal package.json if missing" do
    temp_dir = @builder.send(:create_temp_directory)
    @builder.instance_variable_set(:@temp_dir, temp_dir)
    
    @builder.send(:create_minimal_package_json)
    
    assert File.exist?(temp_dir.join('package.json'))
    
    package_json = JSON.parse(File.read(temp_dir.join('package.json')))
    assert_equal "app-#{@app.id}", package_json['name']
    assert package_json['dependencies']['react']
    assert package_json['devDependencies']['vite']
    
    # Cleanup
    FileUtils.rm_rf(temp_dir) if Dir.exist?(temp_dir)
  end
  
  test "wraps built code for Worker deployment" do
    built_code = "console.log('test app');"
    wrapped = @builder.send(:wrap_for_worker_deployment, built_code)
    
    assert_includes wrapped, built_code
    assert_includes wrapped, 'export default'
    assert_includes wrapped, 'async fetch(request, env, ctx)'
    assert_includes wrapped, 'SUPABASE_SECRET_KEY'
    assert_includes wrapped, 'serveReactApp'
    assert_includes wrapped, 'handleApiRequest'
  end
  
  test "generates default HTML fallback" do
    html = @builder.send(:generate_default_html)
    
    assert_includes html, '<!DOCTYPE html>'
    assert_includes html, '<div id="root"></div>'
    assert_includes html, "App #{@app.id}"
  end
  
  test "build_for_preview uses development mode" do
    # Mock the build process
    @builder.stub :execute_build, { success: true, built_code: 'test', build_time: 45 } do
      @builder.stub :build_with_mode, 'built_code' do
        result = @builder.build_for_preview
        
        assert result[:success]
        assert_equal 45, result[:build_time]
      end
    end
  end
  
  test "build_for_production uses production mode" do
    # Mock the build process
    @builder.stub :execute_build, { success: true, built_code: 'test', build_time: 180 } do
      @builder.stub :build_with_mode, 'built_code' do
        result = @builder.build_for_production
        
        assert result[:success]
        assert_equal 180, result[:build_time]
      end
    end
  end
  
  test "handles build failures gracefully" do
    @builder.stub :create_temp_directory, Rails.root.join('tmp', 'test') do
      @builder.stub :write_app_files_to_disk, nil do
        @builder.stub :build_with_mode, -> { raise "Build failed!" } do
          @builder.stub :cleanup_temp_directory, nil do
            result = @builder.build_for_preview
            
            assert_not result[:success]
            assert_equal "Build failed!", result[:error]
          end
        end
      end
    end
  end
  
  test "cleans up temp directory after build" do
    temp_dir = nil
    
    @builder.stub :create_temp_directory, -> {
      temp_dir = Rails.root.join('tmp', 'test_build')
      FileUtils.mkdir_p(temp_dir)
      temp_dir
    } do
      @builder.stub :write_app_files_to_disk, nil do
        @builder.stub :build_with_mode, 'code' do
          @builder.build_for_preview
          
          # Temp dir should be cleaned up
          assert_not Dir.exist?(temp_dir)
        end
      end
    end
  end
end