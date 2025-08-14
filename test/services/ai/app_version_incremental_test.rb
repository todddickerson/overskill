require 'test_helper'

class Ai::AppVersionIncrementalTest < ActiveSupport::TestCase
  setup do
    # Create test user
    @user = User.create!(
      email: "test_version_#{SecureRandom.hex(4)}@example.com",
      password: 'password123',
      password_confirmation: 'password123',
      first_name: 'Test',
      last_name: 'User',
      time_zone: 'UTC'
    )
    
    # Create test team
    @team = @user.teams.create!(
      name: "Test Team #{SecureRandom.hex(4)}"
    )
    
    # Create test membership
    @membership = @team.memberships.find_by(user: @user) || 
                  @team.memberships.create!(user: @user, roles: ['admin'])
    
    # Create test app
    @app = @team.apps.create!(
      name: "Test App",
      status: 'generating',
      prompt: 'Test prompt',
      creator: @membership,
      app_type: 'tool'
    )
  end
  
  test "incremental versioning tracks created files" do
    # Create initial version with some files
    version1 = @app.app_versions.create!(
      version_number: '1.0.0',
      changelog: 'Initial version',
      user: @user,
      team: @team
    )
    
    file1 = @app.app_files.create!(
      path: 'src/App.tsx',
      content: 'const App = () => { return <div>Hello</div>; }',
      file_type: 'typescript',
      team: @team
    )
    
    file2 = @app.app_files.create!(
      path: 'src/index.ts',
      content: 'import App from "./App";',
      file_type: 'typescript',
      team: @team
    )
    
    version1.app_version_files.create!(app_file: file1, action: 'created', content: file1.content)
    version1.app_version_files.create!(app_file: file2, action: 'created', content: file2.content)
    
    # Create second version that modifies one file and adds a new one
    version2 = @app.app_versions.create!(
      version_number: '1.1.0',
      changelog: 'Added feature',
      user: @user,
      team: @team
    )
    
    # Update existing file
    file1.update!(content: 'const App = () => { return <div>Hello World!</div>; }')
    version2.app_version_files.create!(
      app_file: file1, 
      action: 'updated',
      content: file1.content
    )
    
    # Add new file
    file3 = @app.app_files.create!(
      path: 'src/utils.ts',
      content: 'export const helper = () => {};',
      file_type: 'typescript',
      team: @team
    )
    version2.app_version_files.create!(
      app_file: file3,
      action: 'created',
      content: file3.content
    )
    
    # File2 remains unchanged - so we don't track it in the version
    
    # Verify version tracking
    assert_equal 2, version1.app_version_files.count
    assert_equal 2, version2.app_version_files.count
    
    assert_equal 1, version2.app_version_files.where(action: 'updated').count
    assert_equal 1, version2.app_version_files.where(action: 'created').count
  end
  
  test "incremental versioning tracks deleted files with content preservation" do
    # Create initial version
    version1 = @app.app_versions.create!(
      version_number: '1.0.0',
      changelog: 'Initial version',
      user: @user,
      team: @team
    )
    
    file_to_delete = @app.app_files.create!(
      path: 'src/deprecated.ts',
      content: 'const oldCode = "preserved for history";',
      file_type: 'typescript',
      team: @team
    )
    
    version1.app_version_files.create!(app_file: file_to_delete, action: 'created', content: file_to_delete.content)
    
    # Create second version that deletes the file
    version2 = @app.app_versions.create!(
      version_number: '2.0.0',
      changelog: 'Removed deprecated code',
      user: @user,
      team: @team
    )
    
    # Track deletion with content preservation
    # In production, the file would be deleted after this tracking
    version2.app_version_files.create!(
      app_file: file_to_delete,
      action: 'deleted',
      content: file_to_delete.content # Preserve content before deletion
    )
    
    # Verify deletion tracking
    deleted_record = version2.app_version_files.find_by(action: 'deleted')
    assert deleted_record.present?
    assert_equal 'const oldCode = "preserved for history";', deleted_record.content
    
    # In production, we would delete the file after tracking
    # file_to_delete.destroy would happen here
  end
  
  test "app_version association is set when generation completes" do
    # Create chat message
    chat_message = AppChatMessage.create!(
      app: @app,
      user: @user,
      role: 'user',
      content: 'Generate a todo app'
    )
    
    # Simulate AI response
    assistant_message = AppChatMessage.create!(
      app: @app,
      user: @user,
      role: 'assistant',
      content: 'I will create a todo app for you.',
      is_code_generation: false # Initially false
    )
    
    # Create app version for the generation
    app_version = @app.app_versions.create!(
      version_number: '1.0.0',
      changelog: 'Generated todo app',
      user: @user,
      team: @team
    )
    
    # Simulate generation completion
    assistant_message.update!(
      app_version: app_version,
      is_code_generation: true
    )
    
    # Verify associations
    assert_equal app_version, assistant_message.app_version
    assert assistant_message.is_code_generation
  end
  
  test "version metadata tracks change counts" do
    version = @app.app_versions.create!(
      version_number: '1.0.0',
      changelog: 'Test version',
      user: @user,
      team: @team,
      metadata: {
        'files_created' => 5,
        'files_updated' => 3,
        'files_deleted' => 1,
        'total_changes' => 9
      }
    )
    
    assert_equal 5, version.metadata['files_created']
    assert_equal 3, version.metadata['files_updated']
    assert_equal 1, version.metadata['files_deleted']
    assert_equal 9, version.metadata['total_changes']
  end
end