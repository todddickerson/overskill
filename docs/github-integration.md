# OverSkill GitHub Integration Architecture

## Overview

Every OverSkill app gets its own GitHub repository under the OverSkill organization. This provides full version control, collaboration features, and seamless integration with the developer ecosystem.

## GitHub Organization Structure

```yaml
Organization: overskill-apps
Repository Naming: [username]-[app-slug]
Example: johndoe-todo-tracker

Repository Structure:
├── README.md          # Auto-generated docs
├── .gitignore         # Appropriate ignores
├── package.json       # Dependencies
├── src/              # Source files
├── public/           # Static assets
├── .overskill/       # Platform metadata
│   ├── config.json   # App configuration
│   └── deploy.json   # Deployment settings
└── LICENSE           # MIT by default
```

## Implementation Architecture

### 1. GitHub App Setup

```ruby
# config/initializers/github.rb
Rails.application.config.github = {
  app_id: ENV['GITHUB_APP_ID'],
  private_key: ENV['GITHUB_PRIVATE_KEY'],
  organization: 'overskill-apps',
  webhook_secret: ENV['GITHUB_WEBHOOK_SECRET']
}

# GitHub App permissions needed:
# - Repository: Read & Write
# - Issues: Read & Write  
# - Pull Requests: Read & Write
# - Webhooks: Read
# - Members: Read
```

### 2. Repository Manager Service

```ruby
# app/services/github/repository_manager.rb
module Github
  class RepositoryManager
    include Rails.application.routes.url_helpers
    
    def initialize(app)
      @app = app
      @client = github_client
    end
    
    def create_repository
      repo_name = generate_repo_name
      
      begin
        # Create repository
        repo = @client.create_repository(
          repo_name,
          organization: 'overskill-apps',
          private: @app.private?,
          description: @app.description,
          homepage: app_url(@app),
          has_issues: true,
          has_wiki: false,
          auto_init: false
        )
        
        # Store repo info
        @app.update!(
          github_repo_name: repo.full_name,
          github_repo_url: repo.html_url,
          github_clone_url: repo.clone_url
        )
        
        # Initial commit with all files
        create_initial_commit(repo)
        
        # Set up webhooks
        setup_webhooks(repo)
        
        # Add deploy key for our platform
        add_deploy_key(repo)
        
        repo
      rescue Octokit::UnprocessableEntity => e
        handle_creation_error(e)
      end
    end
    
    def commit_changes(message, changes)
      return unless @app.github_repo_name
      
      # Get current SHA
      ref = @client.ref(@app.github_repo_name, 'heads/main')
      sha = ref.object.sha
      
      # Get base tree
      base_tree = @client.commit(@app.github_repo_name, sha).commit.tree.sha
      
      # Create blobs for changed files
      blobs = changes.map do |change|
        blob_sha = @client.create_blob(
          @app.github_repo_name,
          Base64.encode64(change[:content]),
          'base64'
        )
        
        {
          path: change[:path],
          mode: '100644',
          type: 'blob',
          sha: blob_sha
        }
      end
      
      # Create tree
      tree = @client.create_tree(@app.github_repo_name, blobs, base_tree: base_tree)
      
      # Create commit
      commit = @client.create_commit(
        @app.github_repo_name,
        message,
        tree.sha,
        sha,
        author: {
          name: @app.user.name,
          email: @app.user.email,
          date: Time.current.iso8601
        }
      )
      
      # Update reference
      @client.update_ref(@app.github_repo_name, 'heads/main', commit.sha)
      
      # Create app version record
      @app.versions.create!(
        commit_sha: commit.sha,
        commit_message: message,
        user: @app.user,
        changed_files: changes.map { |c| c[:path] }
      )
    end
    
    def get_commit_history(limit: 20)
      return [] unless @app.github_repo_name
      
      commits = @client.commits(@app.github_repo_name, per_page: limit)
      
      commits.map do |commit|
        {
          sha: commit.sha,
          message: commit.commit.message,
          author: commit.commit.author.name,
          date: commit.commit.author.date,
          url: commit.html_url
        }
      end
    end
    
    def get_file_history(file_path)
      return [] unless @app.github_repo_name
      
      commits = @client.commits(@app.github_repo_name, path: file_path)
      
      commits.map do |commit|
        {
          sha: commit.sha,
          message: commit.commit.message,
          date: commit.commit.author.date,
          diff: get_file_diff(commit.sha, file_path)
        }
      end
    end
    
    private
    
    def github_client
      Octokit::Client.new(
        client_id: Rails.configuration.github[:app_id],
        client_secret: Rails.configuration.github[:private_key]
      )
    end
    
    def generate_repo_name
      base = "#{@app.user.username}-#{@app.slug}"
      base.downcase.gsub(/[^a-z0-9\-]/, '-')
    end
    
    def create_initial_commit(repo)
      files_to_commit = prepare_files_for_commit
      
      # Create blobs
      blobs = files_to_commit.map do |file|
        sha = @client.create_blob(
          repo.full_name,
          Base64.encode64(file[:content]),
          'base64'
        )
        
        {
          path: file[:path],
          mode: '100644',
          type: 'blob',
          sha: sha
        }
      end
      
      # Add README and metadata
      blobs << create_readme_blob(repo)
      blobs << create_overskill_config_blob(repo)
      
      # Create tree and initial commit
      tree = @client.create_tree(repo.full_name, blobs)
      
      commit = @client.create_commit(
        repo.full_name,
        'Initial commit from OverSkill',
        tree.sha,
        [],
        author: {
          name: 'OverSkill Platform',
          email: 'bot@overskill.app',
          date: Time.current.iso8601
        }
      )
      
      # Create main branch
      @client.create_ref(repo.full_name, 'heads/main', commit.sha)
    end
    
    def setup_webhooks(repo)
      @client.create_hook(
        repo.full_name,
        'web',
        {
          url: github_webhook_url,
          content_type: 'json',
          secret: Rails.configuration.github[:webhook_secret]
        },
        {
          events: ['push', 'pull_request', 'issues'],
          active: true
        }
      )
    end
    
    def add_deploy_key(repo)
      key_pair = SSHKey.generate(comment: "overskill-deploy@#{@app.slug}")
      
      @client.add_deploy_key(
        repo.full_name,
        "OverSkill Deploy Key",
        key_pair.ssh_public_key,
        read_only: false
      )
      
      # Store private key securely
      @app.update!(github_deploy_key: encrypt(key_pair.private_key))
    end
  end
end
```

### 3. GitHub Webhook Handler

```ruby
# app/controllers/webhooks/github_controller.rb
module Webhooks
  class GithubController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :verify_github_signature
    
    def create
      case request.headers['X-GitHub-Event']
      when 'push'
        handle_push_event
      when 'pull_request'
        handle_pull_request_event
      when 'issues'
        handle_issues_event
      end
      
      head :ok
    end
    
    private
    
    def handle_push_event
      payload = JSON.parse(request.body.read)
      repo_name = payload['repository']['full_name']
      
      app = App.find_by(github_repo_name: repo_name)
      return unless app
      
      # Skip if push is from our platform
      return if payload['pusher']['email'] == 'bot@overskill.app'
      
      # Sync changes back to our platform
      SyncGithubChangesJob.perform_later(app, payload['after'])
      
      # Update version tracking
      payload['commits'].each do |commit|
        app.versions.create!(
          commit_sha: commit['id'],
          commit_message: commit['message'],
          user: app.users.find_by(email: commit['author']['email']),
          external_commit: true
        )
      end
    end
    
    def verify_github_signature
      signature = 'sha256=' + OpenSSL::HMAC.hexdigest(
        OpenSSL::Digest.new('sha256'),
        Rails.configuration.github[:webhook_secret],
        request.body.read
      )
      
      unless Rack::Utils.secure_compare(signature, request.headers['X-Hub-Signature-256'])
        head :unauthorized
      end
    end
  end
end
```

### 4. User Interface Components

```erb
<!-- app/views/apps/_github_integration.html.erb -->
<div class="github-integration-panel">
  <% if @app.github_repo_name.present? %>
    <div class="flex items-center justify-between mb-4">
      <h3 class="text-lg font-semibold">GitHub Repository</h3>
      <a href="<%= @app.github_repo_url %>" target="_blank" class="btn btn-sm">
        View on GitHub →
      </a>
    </div>
    
    <!-- Recent Commits -->
    <div class="commits-list">
      <h4 class="text-sm font-medium mb-2">Recent Changes</h4>
      <% @commits.each do |commit| %>
        <div class="commit-item">
          <div class="flex items-start">
            <div class="commit-hash">
              <%= link_to commit[:sha][0..6], commit[:url], target: '_blank' %>
            </div>
            <div class="flex-1 ml-3">
              <p class="text-sm"><%= commit[:message] %></p>
              <p class="text-xs text-gray-500">
                by <%= commit[:author] %> • <%= time_ago_in_words(commit[:date]) %> ago
              </p>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    
    <!-- Diff Viewer -->
    <div class="diff-viewer mt-4" data-controller="diff-viewer">
      <h4 class="text-sm font-medium mb-2">File Changes</h4>
      <div data-diff-viewer-target="content">
        <!-- Diff content loaded via Stimulus -->
      </div>
    </div>
  <% else %>
    <div class="text-center py-8">
      <h3 class="text-lg font-semibold mb-2">Enable Version Control</h3>
      <p class="text-gray-600 mb-4">
        Get full Git history, collaborate with others, and integrate with CI/CD
      </p>
      <%= button_to "Create GitHub Repository", 
          app_github_integration_path(@app),
          method: :post,
          class: "btn btn-primary" %>
    </div>
  <% end %>
</div>
```

### 5. Collaboration Features

```ruby
# app/models/app_collaborator.rb
class AppCollaborator < ApplicationRecord
  belongs_to :app
  belongs_to :user
  
  enum role: { viewer: 0, contributor: 1, admin: 2 }
  
  after_create :grant_github_access
  after_destroy :revoke_github_access
  
  private
  
  def grant_github_access
    return unless app.github_repo_name
    
    Github::CollaboratorManager.new(app).add_collaborator(
      user.github_username,
      permission: github_permission_level
    )
  end
  
  def github_permission_level
    case role
    when 'viewer' then 'pull'
    when 'contributor' then 'push'
    when 'admin' then 'admin'
    end
  end
end
```

### 6. Advanced Features

```ruby
# app/services/github/advanced_features.rb
module Github
  class AdvancedFeatures
    def initialize(app)
      @app = app
      @client = github_client
    end
    
    def create_pull_request(title, body, branch)
      @client.create_pull_request(
        @app.github_repo_name,
        'main',
        branch,
        title,
        body
      )
    end
    
    def enable_github_pages
      @client.create_pages_site(
        @app.github_repo_name,
        {
          source: {
            branch: 'main',
            path: '/'
          }
        }
      )
      
      # Update app with GitHub Pages URL
      pages_url = "https://overskill-apps.github.io/#{@app.github_repo_name}/"
      @app.update!(github_pages_url: pages_url)
    end
    
    def create_issue(title, body, labels = [])
      @client.create_issue(
        @app.github_repo_name,
        title,
        body,
        labels: labels
      )
    end
    
    def setup_actions_workflow
      workflow = generate_ci_workflow
      
      @client.create_contents(
        @app.github_repo_name,
        '.github/workflows/ci.yml',
        'Add CI/CD workflow',
        workflow
      )
    end
    
    def fork_for_user(user)
      fork = @client.fork(@app.github_repo_name, organization: user.github_username)
      
      # Create a new app record for the fork
      forked_app = @app.dup
      forked_app.update!(
        user: user,
        name: "#{@app.name} (Fork)",
        github_repo_name: fork.full_name,
        forked_from: @app
      )
      
      forked_app
    end
  end
end
```

### 7. Database Schema Updates

```ruby
# db/migrate/add_github_integration_to_apps.rb
class AddGithubIntegrationToApps < ActiveRecord::Migration[7.1]
  def change
    add_column :apps, :github_repo_name, :string
    add_column :apps, :github_repo_url, :string
    add_column :apps, :github_clone_url, :string
    add_column :apps, :github_deploy_key_encrypted, :text
    add_column :apps, :github_pages_url, :string
    add_column :apps, :enable_github_sync, :boolean, default: true
    add_column :apps, :last_github_sync_at, :datetime
    
    add_index :apps, :github_repo_name, unique: true
    
    create_table :app_versions do |t|
      t.references :app, null: false
      t.references :user
      t.string :commit_sha
      t.string :commit_message
      t.text :changed_files, array: true, default: []
      t.boolean :external_commit, default: false
      t.boolean :deployed, default: false
      t.timestamps
    end
    
    create_table :app_collaborators do |t|
      t.references :app, null: false
      t.references :user, null: false
      t.integer :role, default: 0
      t.string :github_username
      t.timestamps
    end
    
    add_index :app_collaborators, [:app_id, :user_id], unique: true
  end
end
```

## Configuration & Setup

### 1. GitHub App Creation

```yaml
# Create at: https://github.com/settings/apps/new

App Name: OverSkill Platform
Homepage URL: https://overskill.app
Webhook URL: https://overskill.app/webhooks/github
Webhook Secret: [generate strong secret]

Permissions:
  Repository:
    - Contents: Read & Write
    - Issues: Read & Write
    - Pull requests: Read & Write
    - Actions: Write
    - Pages: Write
    - Webhooks: Read & Write
    
  Organization:
    - Members: Read
    
Events:
  - Push
  - Pull request
  - Issues
  - Issue comment
```

### 2. Environment Variables

```bash
# .env
GITHUB_APP_ID=123456
GITHUB_APP_SLUG=overskill-platform
GITHUB_PRIVATE_KEY="-----BEGIN RSA PRIVATE KEY-----..."
GITHUB_WEBHOOK_SECRET=your-webhook-secret
GITHUB_ORGANIZATION=overskill-apps
```

### 3. Background Jobs

```ruby
# app/jobs/sync_github_changes_job.rb
class SyncGithubChangesJob < ApplicationJob
  def perform(app, commit_sha)
    # Fetch changes from GitHub
    changes = Github::RepositoryManager.new(app).get_commit_changes(commit_sha)
    
    # Update local files
    changes.each do |change|
      file = app.app_files.find_or_initialize_by(path: change[:path])
      
      case change[:action]
      when 'added', 'modified'
        file.update!(content: change[:content])
      when 'removed'
        file.destroy
      end
    end
    
    # Rebuild and redeploy
    AppDeploymentJob.perform_later(app) if app.auto_deploy?
  end
end
```

## Benefits of This Approach

1. **Full Version History**: Every change tracked in Git
2. **Collaboration**: Multiple users can work on same app
3. **External Tools**: Use VS Code, GitHub Copilot, etc.
4. **CI/CD Ready**: GitHub Actions for testing/deployment
5. **Fork & Customize**: Users can fork and modify apps
6. **Issue Tracking**: Built-in bug reports and features
7. **GitHub Pages**: Free hosting option for static apps

## Cost Analysis

```yaml
GitHub Organization (Business):
  - $21/user/month
  - Unlimited private repos
  - Advanced security features
  
At Scale (1000 apps):
  - ~$200/month for organization
  - $0.20 per app per month
  - Negligible compared to revenue
```

## User Experience Flow

1. **App Creation**: Automatic repo creation
2. **Every Save**: Commits changes with message
3. **History View**: See all changes in-app
4. **Collaborate**: Invite others via UI
5. **Export**: Clone URL for local development
6. **Fork**: One-click fork for customization

This gives users professional version control without complexity! 🚀