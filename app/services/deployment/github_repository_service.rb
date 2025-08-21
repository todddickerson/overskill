# GitHub Repository Service for Fork-Based App Creation
# Supports ultra-fast app generation via repository forking (2-3 seconds)
# Privacy-first with app.obfuscated_id usage throughout

class Deployment::GithubRepositoryService
  include HTTParty
  base_uri 'https://api.github.com'

  def initialize(app)
    @app = app
    @github_org = ENV['GITHUB_ORG']
    @template_repo = ENV['GITHUB_TEMPLATE_REPO']
    
    # Validate required environment variables first
    missing_vars = []
    missing_vars << 'GITHUB_ORG' if @github_org.blank?
    missing_vars << 'GITHUB_TEMPLATE_REPO' if @template_repo.blank?
    
    if missing_vars.any?
      error_msg = "Missing required environment variables: #{missing_vars.join(', ')}"
      Rails.logger.error "[GithubRepositoryService] #{error_msg}"
      raise error_msg
    end
    
    # Use GitHub App authentication instead of direct token
    authenticator = Deployment::GithubAppAuthenticator.new
    @github_token = authenticator.get_installation_token(@github_org)
    
    if @github_token.blank?
      error_msg = "Failed to generate GitHub installation token. Check GITHUB_APP_PRIVATE_KEY environment variable and GitHub App installation."
      Rails.logger.error "[GithubRepositoryService] #{error_msg}"
      Rails.logger.error "[GithubRepositoryService] Organization: #{@github_org}"
      Rails.logger.error "[GithubRepositoryService] Make sure the GitHub App is installed for organization: #{@github_org}"
      raise error_msg
    end
    
    Rails.logger.info "[GithubRepositoryService] Successfully initialized for app #{app.id} with org #{@github_org}"
    
    self.class.headers({
      'Authorization' => "Bearer #{@github_token}",
      'Accept' => 'application/vnd.github.v3+json',
      'User-Agent' => 'OverSkill-GitHubMigration/1.0'
    })
  end

  # Create new repository instead of forking (works with private repos and Actions)
  def create_app_repository_via_new_repo
    repo_name = generate_unique_repo_name
    
    Rails.logger.info "[GitHubRepositoryService] Creating new repository: #{repo_name}"
    
    begin
      # Step 1: Create a new repository (not a fork)
      create_response = self.class.post("/orgs/#{@github_org}/repos",
        body: {
          name: repo_name,
          description: "AI-generated app by OverSkill - #{@app.name}",
          private: true,
          auto_init: true,  # Initialize with README
          has_issues: false,
          has_projects: false,
          has_wiki: false
        }.to_json,
        headers: self.class.headers.merge('Content-Type' => 'application/json')
      )
      
      unless create_response.success?
        return { success: false, error: "Repository creation failed: #{create_response.code} - #{create_response.body}" }
      end
      
      repo_data = create_response.parsed_response
      
      # Step 2: Update app record
      @app.update!(
        github_repo: "#{@github_org}/#{repo_name}",
        repository_url: repo_data['html_url'],
        repository_name: repo_name,
        github_repo_id: repo_data['id'],
        repository_status: 'ready'
      )
      
      Rails.logger.info "[GitHubRepositoryService] ✅ Repository created successfully: #{repo_data['html_url']}"
      
      # Step 3: Copy template files from local template
      Rails.logger.info "[GitHubRepositoryService] Copying template files..."
      template_result = copy_template_files
      if template_result[:success]
        Rails.logger.info "[GitHubRepositoryService] ✅ Template files copied"
      else
        Rails.logger.error "[GitHubRepositoryService] ⚠️ Failed to copy template files: #{template_result[:error]}"
      end
      
      # Step 4: Update configuration files
      Rails.logger.info "[GitHubRepositoryService] Updating configuration..."
      config_result = update_wrangler_config
      if config_result[:success]
        Rails.logger.info "[GitHubRepositoryService] ✅ Configuration updated"
      else
        Rails.logger.error "[GitHubRepositoryService] ⚠️ Failed to update configuration: #{config_result[:error]}"
      end
      
      # Step 5: Add GitHub Actions workflow
      Rails.logger.info "[GitHubRepositoryService] Adding GitHub Actions workflow..."
      workflow_result = add_deployment_workflow
      if workflow_result[:success]
        Rails.logger.info "[GitHubRepositoryService] ✅ GitHub Actions workflow added"
      else
        Rails.logger.error "[GitHubRepositoryService] ⚠️ Failed to add workflow: #{workflow_result[:error]}"
      end
      
      { success: true, repository_url: repo_data['html_url'], repository_name: repo_name }
    rescue => e
      Rails.logger.error "[GitHubRepositoryService] Repository creation error: #{e.message}"
      { success: false, error: e.message }
    end
  end
  
  # Fork-based repository creation for ultra-fast app generation (2-3 seconds)
  # NOTE: This doesn't work with private repos - Actions won't run on private forks
  def create_app_repository_via_fork
    repo_name = generate_unique_repo_name
    
    Rails.logger.info "[GitHubRepositoryService] Creating repository via fork: #{repo_name}"
    
    begin
      # Step 1: Fork the template repository (near-instant)
      fork_response = fork_template_repository(repo_name)
      return { success: false, error: "Fork failed: #{fork_response}" } unless fork_response.success?
      
      fork_data = fork_response.parsed_response
      
      # Step 2: Update app record immediately (repository is ready)
      @app.update!(
        github_repo: "Overskill-apps/#{repo_name}",  # Full GitHub repo name
        repository_url: fork_data['html_url'],
        repository_name: repo_name,
        github_repo_id: fork_data['id'],
        repository_status: 'ready'
      )
      
      Rails.logger.info "[GitHubRepositoryService] ✅ Repository forked successfully: #{fork_data['html_url']}"
      
      # Step 2.5: Enable GitHub Actions for the forked repository
      Rails.logger.info "[GitHubRepositoryService] Enabling GitHub Actions..."
      actions_result = enable_github_actions(repo_name)
      if actions_result[:success]
        Rails.logger.info "[GitHubRepositoryService] ✅ GitHub Actions enabled"
      else
        Rails.logger.warn "[GitHubRepositoryService] ⚠️ Failed to enable GitHub Actions: #{actions_result[:error]}"
      end
      
      # Step 3: Update wrangler.toml with actual values
      Rails.logger.info "[GitHubRepositoryService] Updating wrangler.toml configuration..."
      wrangler_result = update_wrangler_config
      if wrangler_result[:success]
        Rails.logger.info "[GitHubRepositoryService] ✅ Wrangler config updated"
      else
        Rails.logger.error "[GitHubRepositoryService] ⚠️ Failed to update wrangler.toml: #{wrangler_result[:error]}"
      end
      
      # Note: Workflow file will be added during file push in DeployAppJob
      # This ensures it's added with the app files in a single commit
      
      {
        success: true,
        repository: fork_data,
        repo_name: repo_name,
        ready: true,
        fork_time: '2-3 seconds'
      }
    rescue => e
      Rails.logger.error "[GitHubRepositoryService] Fork creation failed: #{e.message}"
      { success: false, error: e.message }
    end
  end

  # Update files in the forked repository with retry logic for SHA conflicts
  def update_file_in_repository(path:, content:, message:, branch: 'main', retry_count: 0)
    repo_full_name = "#{@github_org}/#{@app.repository_name}"
    
    Rails.logger.info "[GitHubRepositoryService] Updating file: #{path} in #{repo_full_name}"
    
    begin
      # Check if file exists (to get SHA for updates)
      get_response = self.class.get("/repos/#{repo_full_name}/contents/#{path}", 
        headers: self.class.headers,
        query: { ref: branch }
      )
      
      # Prepare request body
      body = {
        message: message,
        content: Base64.strict_encode64(content),
        branch: branch
      }
      
      # Add SHA if file exists (for updates)
      if get_response.success?
        body[:sha] = get_response.parsed_response['sha']
      end
      
      # Create or update the file
      response = self.class.put("/repos/#{repo_full_name}/contents/#{path}", 
        body: body.to_json,
        headers: self.class.headers.merge('Content-Type' => 'application/json')
      )
      
      if response.success?
        Rails.logger.info "[GitHubRepositoryService] ✅ File updated: #{path}"
        { success: true, sha: response.parsed_response.dig('content', 'sha') }
      elsif response.code == 409 && retry_count < 3
        # SHA conflict - another process updated the file
        Rails.logger.warn "[GitHubRepositoryService] SHA conflict for #{path}, retrying (attempt #{retry_count + 1}/3)"
        
        # Wait a bit before retrying to reduce collision chance
        sleep(0.5 * (retry_count + 1))
        
        # Retry with fresh SHA
        update_file_in_repository(path: path, content: content, message: message, branch: branch, retry_count: retry_count + 1)
      else
        Rails.logger.error "[GitHubRepositoryService] File update failed: #{response.code} - #{response.body}"
        { success: false, error: "GitHub API error: #{response.code}", details: response.body }
      end
    rescue => e
      Rails.logger.error "[GitHubRepositoryService] File update exception: #{e.message}"
      { success: false, error: e.message }
    end
  end

  # Push multiple files as part of app generation (single atomic commit)
  def push_file_structure(file_structure)
    Rails.logger.info "[GitHubRepositoryService] Pushing #{file_structure.size} files to repository as single commit"
    
    # Use batch commit for all files at once (single workflow trigger)
    result = batch_commit_files(file_structure)
    
    if result[:success]
      Rails.logger.info "[GitHubRepositoryService] ✅ Successfully committed #{file_structure.size} files in single commit"
      { success: true, files_pushed: file_structure.size, commit_sha: result[:commit_sha] }
    else
      Rails.logger.error "[GitHubRepositoryService] ❌ Batch commit failed: #{result[:error]}"
      { success: false, error: result[:error], files_pushed: 0 }
    end
  end
  
  # Commit multiple files atomically using GitHub Tree API
  def batch_commit_files(file_structure, message: nil)
    return { success: false, error: 'No repository created' } unless @app.repository_name
    
    repo_full_name = "#{@github_org}/#{@app.repository_name}"
    
    # Generate appropriate commit message
    commit_message = message || generate_app_version_commit_message(file_structure)
    
    Rails.logger.info "[GitHubRepositoryService] Creating atomic commit: #{commit_message}"
    
    begin
      # Get current HEAD commit
      ref_response = self.class.get("/repos/#{repo_full_name}/git/ref/heads/main", headers: self.class.headers)
      unless ref_response.success?
        return { success: false, error: "Failed to get HEAD ref: #{ref_response.code}" }
      end
      
      head_sha = ref_response.parsed_response.dig('object', 'sha')
      
      # Get current tree
      head_commit_response = self.class.get("/repos/#{repo_full_name}/git/commits/#{head_sha}", headers: self.class.headers)
      unless head_commit_response.success?
        return { success: false, error: "Failed to get HEAD commit: #{head_commit_response.code}" }
      end
      
      base_tree_sha = head_commit_response.parsed_response.dig('tree', 'sha')
      
      # Create blobs for each file
      tree_items = []
      file_structure.each do |path, content|
        # Create blob
        blob_response = self.class.post("/repos/#{repo_full_name}/git/blobs",
          body: { content: content, encoding: 'utf-8' }.to_json,
          headers: self.class.headers.merge('Content-Type' => 'application/json')
        )
        
        unless blob_response.success?
          return { success: false, error: "Failed to create blob for #{path}: #{blob_response.code}" }
        end
        
        blob_sha = blob_response.parsed_response['sha']
        
        tree_items << {
          path: path,
          mode: '100644', # Regular file
          type: 'blob',
          sha: blob_sha
        }
      end
      
      # Create new tree
      tree_response = self.class.post("/repos/#{repo_full_name}/git/trees",
        body: { base_tree: base_tree_sha, tree: tree_items }.to_json,
        headers: self.class.headers.merge('Content-Type' => 'application/json')
      )
      
      unless tree_response.success?
        return { success: false, error: "Failed to create tree: #{tree_response.code}" }
      end
      
      new_tree_sha = tree_response.parsed_response['sha']
      
      # Create commit
      commit_response = self.class.post("/repos/#{repo_full_name}/git/commits",
        body: {
          message: commit_message,
          tree: new_tree_sha,
          parents: [head_sha],
          author: {
            name: 'OverSkill App Builder',
            email: 'noreply@overskill.com'
          }
        }.to_json,
        headers: self.class.headers.merge('Content-Type' => 'application/json')
      )
      
      unless commit_response.success?
        return { success: false, error: "Failed to create commit: #{commit_response.code}" }
      end
      
      new_commit_sha = commit_response.parsed_response['sha']
      
      # Update HEAD to point to new commit
      update_ref_response = self.class.patch("/repos/#{repo_full_name}/git/refs/heads/main",
        body: { sha: new_commit_sha }.to_json,
        headers: self.class.headers.merge('Content-Type' => 'application/json')
      )
      
      unless update_ref_response.success?
        return { success: false, error: "Failed to update HEAD: #{update_ref_response.code}" }
      end
      
      Rails.logger.info "[GitHubRepositoryService] ✅ Atomic commit created: #{new_commit_sha}"
      { success: true, commit_sha: new_commit_sha, tree_sha: new_tree_sha }
      
    rescue => e
      Rails.logger.error "[GitHubRepositoryService] Batch commit exception: #{e.message}"
      { success: false, error: e.message }
    end
  end

  # Set up GitHub repository secrets for Cloudflare Workers deployment
  def setup_deployment_secrets
    return { success: false, error: 'No repository created' } unless @app.repository_name
    
    repo_full_name = "#{@github_org}/#{@app.repository_name}"
    Rails.logger.info "[GitHubRepositoryService] Setting up deployment secrets for #{repo_full_name}"
    
    # Required secrets for GitHub Actions workflow
    secrets = {
      'CLOUDFLARE_API_TOKEN' => ENV['CLOUDFLARE_API_TOKEN'],
      'CLOUDFLARE_ACCOUNT_ID' => ENV['CLOUDFLARE_ACCOUNT_ID']
    }
    
    results = []
    
    secrets.each do |name, value|
      next unless value.present?
      
      result = set_repository_secret(repo_full_name, name, value)
      results << { name: name, success: result[:success], error: result[:error] }
    end
    
    success_count = results.count { |r| r[:success] }
    total_count = results.size
    
    if success_count == total_count
      Rails.logger.info "[GitHubRepositoryService] ✅ All #{total_count} secrets configured"
      { success: true, secrets_configured: total_count }
    else
      failed_secrets = results.reject { |r| r[:success] }
      Rails.logger.error "[GitHubRepositoryService] Failed to configure secrets: #{failed_secrets.map { |s| s[:name] }.join(', ')}"
      { success: false, failed_secrets: failed_secrets }
    end
  end
  
  private
  
  def generate_app_version_commit_message(file_structure)
    file_count = file_structure.size
    
    # Extract some key files for context
    key_files = file_structure.keys.select { |path| 
      path.match?(/\.(tsx|ts|jsx|js|html)$/) && !path.include?('node_modules')
    }.first(3)
    
    if key_files.any?
      sample_files = key_files.map { |path| File.basename(path) }.join(', ')
      "feat: Update app with #{file_count} files (#{sample_files})\n\n🤖 Generated by OverSkill AI App Builder\n✨ Ready for Workers for Platforms deployment"
    else
      "feat: Update app with #{file_count} files\n\n🤖 Generated by OverSkill AI App Builder\n✨ Ready for Workers for Platforms deployment"
    end
  end

  # Get repository information
  def get_repository_info
    return { success: false, error: 'No repository created' } unless @app.repository_name
    
    repo_full_name = "#{@github_org}/#{@app.repository_name}"
    
    response = self.class.get("/repos/#{repo_full_name}", headers: self.class.headers)
    
    if response.success?
      { success: true, repository: response.parsed_response }
    else
      { success: false, error: "Repository not found or access denied" }
    end
  end

  # List repository files for debugging
  def list_repository_files(path: '')
    return { success: false, error: 'No repository created' } unless @app.repository_name
    
    repo_full_name = "#{@github_org}/#{@app.repository_name}"
    
    response = self.class.get("/repos/#{repo_full_name}/contents/#{path}", headers: self.class.headers)
    
    if response.success?
      files = response.parsed_response.map { |file| file['name'] }
      { success: true, files: files }
    else
      { success: false, error: "Could not list files" }
    end
  end

  # Update wrangler.toml with actual values for Workers for Platforms deployment
  def update_wrangler_config
    return { success: false, error: 'No repository created' } unless @app.repository_name
    
    Rails.logger.info "[GitHubRepositoryService] Updating wrangler.toml with actual values"
    
    # Load wrangler template
    wrangler_template_path = Rails.root.join('app/services/ai/templates/overskill_20250728/wrangler.toml')
    
    unless File.exist?(wrangler_template_path)
      return { success: false, error: 'Wrangler template not found' }
    end
    
    # Read template content
    wrangler_content = File.read(wrangler_template_path)
    
    # Replace placeholders with actual values
    customized_wrangler = wrangler_content
      .gsub('{{APP_ID}}', @app.obfuscated_id.downcase)
      .gsub('{{SUPABASE_URL}}', ENV['SUPABASE_URL'] || '')
      .gsub('{{SUPABASE_ANON_KEY}}', ENV['SUPABASE_ANON_KEY'] || '')
      .gsub('{{OWNER_ID}}', @app.team_id.to_s)
    
    # Update the wrangler.toml file in repository
    result = update_file_in_repository(
      path: 'wrangler.toml',
      content: customized_wrangler,
      message: "feat: Configure wrangler.toml for Workers for Platforms deployment\n\n🤖 Auto-configured with app-specific values\n✅ Ready for WFP deployment"
    )
    
    if result[:success]
      Rails.logger.info "[GitHubRepositoryService] ✅ Wrangler config updated successfully"
      { success: true, wrangler_configured: true }
    else
      Rails.logger.error "[GitHubRepositoryService] Failed to update wrangler.toml: #{result[:error]}"
      { success: false, error: result[:error] }
    end
  end
  
  # Add GitHub Actions workflow for automated deployment
  def add_deployment_workflow
    return { success: false, error: 'No repository created' } unless @app.repository_name
    
    Rails.logger.info "[GitHubRepositoryService] Adding deployment workflow to repository"
    
    # Load workflow template and populate with app-specific values
    workflow_template_path = Rails.root.join('app/services/ai/templates/overskill_20250728/.github/workflows/deploy.yml')
    
    unless File.exist?(workflow_template_path)
      return { success: false, error: 'Workflow template not found' }
    end
    
    # Read and customize workflow content
    workflow_content = File.read(workflow_template_path)
    
    # Replace placeholders with actual app values
    customized_workflow = workflow_content
      .gsub('{{APP_ID}}', @app.obfuscated_id.downcase)
      .gsub('{{OWNER_ID}}', @app.team.users.first&.id.to_s || '1')
    
    # Add the workflow file to repository
    result = update_file_in_repository(
      path: '.github/workflows/deploy.yml',
      content: customized_workflow,
      message: "feat: Add automated deployment workflow for Workers for Platforms\n\n🤖 Auto-generated CI/CD pipeline\n✅ Deploys to WFP dispatch namespaces\n🔐 Uses GitHub secrets for authentication"
    )
    
    if result[:success]
      Rails.logger.info "[GitHubRepositoryService] ✅ Deployment workflow added successfully"
      { success: true, workflow_added: true }
    else
      Rails.logger.error "[GitHubRepositoryService] Failed to add workflow: #{result[:error]}"
      { success: false, error: result[:error] }
    end
  end

  private

  # Move workflow file from .workflow-templates to .github/workflows after fork
  def move_workflow_file_post_fork(repo_name)
    repo_full_name = "#{@github_org}/#{repo_name}"
    
    Rails.logger.info "[GitHubRepositoryService] Moving workflow from .workflow-templates to .github/workflows"
    
    begin
      # Get the workflow file from .workflow-templates
      source_response = self.class.get("/repos/#{repo_full_name}/contents/.workflow-templates/deploy.yml",
        headers: self.class.headers
      )
      
      if !source_response.success?
        Rails.logger.warn "[GitHubRepositoryService] No workflow template found at .workflow-templates/deploy.yml"
        return { success: false, error: "No workflow template found" }
      end
      
      # Decode the content
      workflow_content = Base64.decode64(source_response.parsed_response['content'])
      source_sha = source_response.parsed_response['sha']
      
      # Replace placeholders with actual app values
      customized_workflow = workflow_content
        .gsub('{{APP_ID}}', @app.obfuscated_id.downcase)
        .gsub('{{OWNER_ID}}', @app.team.users.first&.id.to_s || '1')
      
      # Create .github/workflows directory structure and add the file
      create_response = self.class.put("/repos/#{repo_full_name}/contents/.github/workflows/deploy.yml",
        body: {
          message: "Activate GitHub Actions workflow",
          content: Base64.strict_encode64(customized_workflow),
          branch: 'main'
        }.to_json,
        headers: self.class.headers.merge('Content-Type' => 'application/json')
      )
      
      if create_response.success?
        Rails.logger.info "[GitHubRepositoryService] ✅ Workflow moved to .github/workflows/deploy.yml"
        
        # Delete the original file from .workflow-templates
        delete_response = self.class.delete("/repos/#{repo_full_name}/contents/.workflow-templates/deploy.yml",
          body: {
            message: "Remove workflow template after moving to .github/workflows",
            sha: source_sha,
            branch: 'main'
          }.to_json,
          headers: self.class.headers.merge('Content-Type' => 'application/json')
        )
        
        if delete_response.success?
          Rails.logger.info "[GitHubRepositoryService] ✅ Removed workflow template from .workflow-templates"
        else
          Rails.logger.warn "[GitHubRepositoryService] Failed to remove template: #{delete_response.code}"
        end
        
        { success: true }
      else
        Rails.logger.error "[GitHubRepositoryService] Failed to create workflow: #{create_response.code} - #{create_response.body}"
        { success: false, error: "Failed to create workflow file: #{create_response.code}" }
      end
    rescue => e
      Rails.logger.error "[GitHubRepositoryService] Workflow move error: #{e.message}"
      { success: false, error: e.message }
    end
  end

  # Enable GitHub Actions for a repository
  def enable_github_actions(repo_name)
    repo_full_name = "#{@github_org}/#{repo_name}"
    
    Rails.logger.info "[GitHubRepositoryService] Enabling Actions for #{repo_full_name}"
    
    begin
      # Enable Actions for the repository
      response = self.class.patch("/repos/#{repo_full_name}/actions/permissions",
        body: { enabled: true, allowed_actions: 'all' }.to_json,
        headers: self.class.headers.merge('Content-Type' => 'application/json')
      )
      
      if response.success?
        Rails.logger.info "[GitHubRepositoryService] ✅ GitHub Actions enabled for #{repo_full_name}"
        { success: true }
      else
        Rails.logger.error "[GitHubRepositoryService] Failed to enable Actions: #{response.code} - #{response.body}"
        { success: false, error: "Failed to enable GitHub Actions: #{response.code}" }
      end
    rescue => e
      Rails.logger.error "[GitHubRepositoryService] Actions enablement error: #{e.message}"
      { success: false, error: e.message }
    end
  end

  def fork_template_repository(new_repo_name)
    fork_body = {
      name: new_repo_name,
      organization: @github_org
    }
    
    # Fork from GITHUB_TEMPLATE_REPO (e.g., "Overskill-apps/vite-app-template")
    self.class.post("/repos/#{@template_repo}/forks", 
      body: fork_body.to_json,
      headers: self.class.headers.merge('Content-Type' => 'application/json')
    )
  end

  # Copy template files from local template directory
  def copy_template_files
    return { success: false, error: 'No repository created' } unless @app.repository_name
    
    template_dir = Rails.root.join('app', 'services', 'ai', 'templates', 'overskill_20250728')
    repo_full_name = "#{@github_org}/#{@app.repository_name}"
    
    Rails.logger.info "[GitHubRepositoryService] Copying template files from #{template_dir}"
    
    begin
      # Read all template files
      template_files = {}
      Dir.glob("#{template_dir}/**/*", File::FNM_DOTMATCH).each do |file_path|
        next if File.directory?(file_path)
        next if file_path.include?('.git/')
        next if file_path.include?('node_modules/')
        
        relative_path = file_path.sub("#{template_dir}/", '')
        content = File.read(file_path)
        template_files[relative_path] = content
      end
      
      Rails.logger.info "[GitHubRepositoryService] Found #{template_files.size} template files to copy"
      
      # Push all files in a single commit
      result = push_file_structure(template_files, "Initialize app from template")
      
      if result[:success]
        Rails.logger.info "[GitHubRepositoryService] ✅ Template files copied successfully"
        { success: true }
      else
        { success: false, error: result[:error] }
      end
    rescue => e
      Rails.logger.error "[GitHubRepositoryService] Template copy error: #{e.message}"
      { success: false, error: e.message }
    end
  end
  
  def generate_unique_repo_name
    # Use obfuscated_id for privacy instead of exposing real app ID
    base_name = @app.name.parameterize
    "#{base_name}-#{@app.obfuscated_id}"
  end

  # Set individual repository secret using GitHub API
  def set_repository_secret(repo_full_name, secret_name, secret_value)
    begin
      # First, get the repository's public key for encryption
      key_response = self.class.get("/repos/#{repo_full_name}/actions/secrets/public-key", 
        headers: self.class.headers)
      
      unless key_response.success?
        return { success: false, error: "Failed to get public key: #{key_response.code}" }
      end
      
      public_key_data = key_response.parsed_response
      
      # Encrypt the secret value using sodium/libsodium (required by GitHub API)
      require 'base64'
      require 'rbnacl'
      
      # Decode the public key
      public_key = Base64.decode64(public_key_data['key'])
      
      # Create a box for encryption
      box = RbNaCl::Boxes::Sealed.from_public_key(public_key)
      
      # Encrypt the secret
      encrypted_value = box.encrypt(secret_value)
      encrypted_value_b64 = Base64.strict_encode64(encrypted_value)
      
      # Set the secret
      secret_body = {
        encrypted_value: encrypted_value_b64,
        key_id: public_key_data['key_id']
      }
      
      response = self.class.put("/repos/#{repo_full_name}/actions/secrets/#{secret_name}",
        body: secret_body.to_json,
        headers: self.class.headers.merge('Content-Type' => 'application/json')
      )
      
      if response.success?
        Rails.logger.info "[GitHubRepositoryService] ✅ Secret #{secret_name} configured"
        { success: true }
      else
        Rails.logger.error "[GitHubRepositoryService] Failed to set secret #{secret_name}: #{response.code}"
        { success: false, error: "GitHub API error: #{response.code}" }
      end
      
    rescue => e
      Rails.logger.error "[GitHubRepositoryService] Secret encryption error: #{e.message}"
      { success: false, error: e.message }
    end
  end
end