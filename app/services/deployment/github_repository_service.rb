# GitHub Repository Service for Fork-Based App Creation
# Supports ultra-fast app generation via repository forking (2-3 seconds)
# Privacy-first with app.obfuscated_id usage throughout

class Deployment::GitHubRepositoryService
  include HTTParty
  base_uri 'https://api.github.com'

  def initialize(app)
    @app = app
    @github_token = ENV['GITHUB_TOKEN']
    @github_org = ENV['GITHUB_ORG']
    @template_repo = ENV['GITHUB_TEMPLATE_REPO']
    
    raise "Missing required environment variables" unless [@github_token, @github_org, @template_repo].all?(&:present?)
    
    self.class.headers({
      'Authorization' => "Bearer #{@github_token}",
      'Accept' => 'application/vnd.github.v3+json',
      'User-Agent' => 'OverSkill-GitHubMigration/1.0'
    })
  end

  # Fork-based repository creation for ultra-fast app generation (2-3 seconds)
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
        repository_url: fork_data['html_url'],
        repository_name: repo_name,
        github_repo_id: fork_data['id'],
        repository_status: 'ready'
      )
      
      Rails.logger.info "[GitHubRepositoryService] ✅ Repository forked successfully: #{fork_data['html_url']}"
      
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

  # Update files in the forked repository
  def update_file_in_repository(path:, content:, message:, branch: 'main')
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
      else
        Rails.logger.error "[GitHubRepositoryService] File update failed: #{response.code} - #{response.body}"
        { success: false, error: "GitHub API error: #{response.code}" }
      end
    rescue => e
      Rails.logger.error "[GitHubRepositoryService] File update exception: #{e.message}"
      { success: false, error: e.message }
    end
  end

  # Push multiple files as part of app generation
  def push_file_structure(file_structure)
    Rails.logger.info "[GitHubRepositoryService] Pushing #{file_structure.size} files to repository"
    
    results = []
    
    file_structure.each do |path, content|
      result = update_file_in_repository(
        path: path,
        content: content,
        message: "AI: Generate #{path}"
      )
      
      results << { path: path, success: result[:success], error: result[:error] }
      
      # Small delay to avoid rate limiting
      sleep(0.1) if file_structure.size > 10
    end
    
    success_count = results.count { |r| r[:success] }
    total_count = results.size
    
    if success_count == total_count
      Rails.logger.info "[GitHubRepositoryService] ✅ All #{total_count} files pushed successfully"
      { success: true, files_pushed: total_count }
    else
      failed_files = results.reject { |r| r[:success] }
      Rails.logger.error "[GitHubRepositoryService] #{failed_files.size} files failed to push"
      { success: false, failed_files: failed_files, partial_success: success_count > 0 }
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

  private

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

  def generate_unique_repo_name
    # Use obfuscated_id for privacy instead of exposing real app ID
    base_name = (@app.slug.presence || @app.name).parameterize
    "#{base_name}-#{@app.obfuscated_id}"
  end
end