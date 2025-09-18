# GitHub Version Tagging Service
# Creates and manages GitHub tags for AppVersions to enable point-in-time restoration
# Tags follow format: v{version_number}-{timestamp} (e.g., v1.2.3-20250821155500)

class Deployment::GithubVersionTaggingService
  include HTTParty
  base_uri "https://api.github.com"

  def initialize(app_version)
    @app_version = app_version
    @app = app_version.app
    @github_org = ENV["GITHUB_ORG"]

    # Use GitHub App authentication
    authenticator = Deployment::GithubAppAuthenticator.new
    @github_token = authenticator.get_installation_token(@github_org)

    raise "Missing required environment variables" unless [@github_token, @github_org].all?(&:present?)
    raise "App has no GitHub repository" unless @app.repository_name.present?

    self.class.headers({
      "Authorization" => "Bearer #{@github_token}",
      "Accept" => "application/vnd.github.v3+json",
      "User-Agent" => "OverSkill-GitHubVersioning/1.0"
    })
  end

  # Create a GitHub tag for this AppVersion
  def create_version_tag(commit_sha = nil)
    repo_full_name = "#{@github_org}/#{@app.repository_name}"

    # Generate tag name: v{version_number}-{timestamp}
    tag_name = generate_tag_name

    Rails.logger.info "[GithubVersionTagging] Creating tag #{tag_name} for AppVersion #{@app_version.id}"

    begin
      # Get the latest commit SHA if not provided
      if commit_sha.blank?
        commit_sha = get_latest_commit_sha
        return {success: false, error: "Could not get latest commit SHA"} if commit_sha.blank?
      end

      # Create annotated tag (more robust than lightweight tags)
      tag_message = build_tag_message

      # Step 1: Create the tag object
      tag_object_response = create_tag_object(repo_full_name, tag_name, commit_sha, tag_message)
      return tag_object_response unless tag_object_response[:success]

      # Step 2: Create the reference
      ref_response = create_tag_reference(repo_full_name, tag_name, tag_object_response[:sha])
      return ref_response unless ref_response[:success]

      # Update AppVersion with tag information
      @app_version.update!(
        github_tag: tag_name,
        github_commit_sha: commit_sha,
        github_tag_url: "https://github.com/#{repo_full_name}/releases/tag/#{tag_name}",
        tagged_at: Time.current
      )

      Rails.logger.info "[GithubVersionTagging] ✅ Successfully created tag #{tag_name}"

      {
        success: true,
        tag_name: tag_name,
        commit_sha: commit_sha,
        tag_url: @app_version.github_tag_url
      }
    rescue => e
      Rails.logger.error "[GithubVersionTagging] Failed to create tag: #{e.message}"
      {success: false, error: e.message}
    end
  end

  # Restore app files from a specific GitHub tag
  def restore_from_tag(target_app_version = nil)
    return {success: false, error: "No GitHub tag associated with this version"} unless @app_version.github_tag.present?

    repo_full_name = "#{@github_org}/#{@app.repository_name}"

    Rails.logger.info "[GithubVersionTagging] Restoring from tag #{@app_version.github_tag}"

    begin
      # Get the tree for this tag
      tree_sha = get_tree_sha_for_tag(@app_version.github_tag)
      return {success: false, error: "Could not get tree SHA for tag"} if tree_sha.blank?

      # Get all files from the tree
      files = get_files_from_tree(repo_full_name, tree_sha)
      return {success: false, error: "Could not retrieve files from tag"} if files.empty?

      # Create new AppVersion if not provided
      if target_app_version.nil?
        target_app_version = @app.app_versions.create!(
          version_number: generate_restoration_version_number,
          team: @app.team,
          user: @app_version.user,
          changelog: "Restored from version #{@app_version.version_number} (tag: #{@app_version.github_tag})",
          deployed: false,
          external_commit: true,
          environment: "preview"
        )
      end

      # Restore files to app
      restored_count = 0
      failed_files = []

      files.each do |file_data|
        # Skip non-essential files
        next if skip_file?(file_data[:path])

        # Get file content
        content = fetch_file_content(repo_full_name, file_data[:path], @app_version.github_tag)
        next if content.nil?

        # Find or create AppFile
        app_file = @app.app_files.find_or_initialize_by(path: file_data[:path])
        app_file.content = content
        app_file.team = @app.team
        app_file.file_type = determine_file_type(file_data[:path])

        if app_file.save
          # Track change in AppVersionFile
          target_app_version.app_version_files.create!(
            app_file: app_file,
            action: app_file.previously_new_record? ? "created" : "updated"
          )
          restored_count += 1
        else
          failed_files << file_data[:path]
        end
      rescue => e
        Rails.logger.error "[GithubVersionTagging] Failed to restore file #{file_data[:path]}: #{e.message}"
        failed_files << file_data[:path]
      end

      # Update target version with snapshot
      target_app_version.update!(
        files_snapshot: @app.app_files.map { |f|
          {path: f.path, content: f.content, file_type: f.file_type}
        }.to_json
      )

      # Generate display name for the restored version
      target_app_version.generate_display_name!

      if failed_files.empty?
        Rails.logger.info "[GithubVersionTagging] ✅ Successfully restored #{restored_count} files from tag #{@app_version.github_tag}"
        {
          success: true,
          restored_count: restored_count,
          version: target_app_version,
          message: "Successfully restored #{restored_count} files from version #{@app_version.version_number}"
        }
      else
        Rails.logger.warn "[GithubVersionTagging] ⚠️ Partially restored. Failed files: #{failed_files.join(", ")}"
        {
          success: false,
          restored_count: restored_count,
          failed_files: failed_files,
          version: target_app_version,
          error: "Partially restored. #{failed_files.size} files failed to restore."
        }
      end
    rescue => e
      Rails.logger.error "[GithubVersionTagging] Restoration failed: #{e.message}"
      {success: false, error: e.message}
    end
  end

  # List all tags for the app
  def list_version_tags
    repo_full_name = "#{@github_org}/#{@app.repository_name}"

    response = self.class.get("/repos/#{repo_full_name}/tags", headers: self.class.headers)

    if response.success?
      tags = response.parsed_response.select { |tag| tag["name"].start_with?("v") }
      {
        success: true,
        tags: tags.map { |t|
          {
            name: t["name"],
            sha: t["commit"]["sha"],
            url: t["commit"]["url"]
          }
        }
      }
    else
      {success: false, error: "Failed to list tags: #{response.code}"}
    end
  end

  private

  def generate_tag_name
    timestamp = Time.current.strftime("%Y%m%d%H%M%S")
    "v#{@app_version.version_number.delete("v")}-#{timestamp}"
  end

  def generate_restoration_version_number
    # Increment patch version with 'restored' suffix
    base_version = @app_version.version_number.delete("v").split(".")
    base_version[2] = (base_version[2].to_i + 1).to_s
    "#{base_version.join(".")}-restored"
  end

  def build_tag_message
    <<~MSG
      Version #{@app_version.version_number}
      
      Changes: #{@app_version.changelog || "No changelog provided"}
      Created: #{@app_version.created_at.iso8601}
      User: #{@app_version.user&.email || "System"}
      
      Files changed: #{@app_version.app_version_files.count}
      
      This tag enables point-in-time restoration of the application state.
    MSG
  end

  def get_latest_commit_sha
    repo_full_name = "#{@github_org}/#{@app.repository_name}"

    response = self.class.get("/repos/#{repo_full_name}/commits/main", headers: self.class.headers)

    if response.success?
      response.parsed_response["sha"]
    else
      Rails.logger.error "[GithubVersionTagging] Failed to get latest commit: #{response.code}"
      nil
    end
  end

  def create_tag_object(repo_full_name, tag_name, commit_sha, message)
    body = {
      tag: tag_name,
      message: message,
      object: commit_sha,
      type: "commit",
      tagger: {
        name: "OverSkill Version Control",
        email: "versions@overskill.com",
        date: Time.current.iso8601
      }
    }

    response = self.class.post("/repos/#{repo_full_name}/git/tags",
      body: body.to_json,
      headers: self.class.headers.merge("Content-Type" => "application/json"))

    if response.success?
      {success: true, sha: response.parsed_response["sha"]}
    else
      Rails.logger.error "[GithubVersionTagging] Failed to create tag object: #{response.code} - #{response.body}"
      {success: false, error: "Failed to create tag object: #{response.code}"}
    end
  end

  def create_tag_reference(repo_full_name, tag_name, tag_sha)
    body = {
      ref: "refs/tags/#{tag_name}",
      sha: tag_sha
    }

    response = self.class.post("/repos/#{repo_full_name}/git/refs",
      body: body.to_json,
      headers: self.class.headers.merge("Content-Type" => "application/json"))

    if response.success?
      {success: true}
    else
      Rails.logger.error "[GithubVersionTagging] Failed to create tag reference: #{response.code} - #{response.body}"
      {success: false, error: "Failed to create tag reference: #{response.code}"}
    end
  end

  def get_tree_sha_for_tag(tag_name)
    repo_full_name = "#{@github_org}/#{@app.repository_name}"

    # Get the tag reference
    response = self.class.get("/repos/#{repo_full_name}/git/refs/tags/#{tag_name}",
      headers: self.class.headers)

    return nil unless response.success?

    tag_sha = response.parsed_response["object"]["sha"]

    # If it's an annotated tag, we need to get the commit it points to
    tag_response = self.class.get("/repos/#{repo_full_name}/git/tags/#{tag_sha}",
      headers: self.class.headers)

    commit_sha = if tag_response.success?
      tag_response.parsed_response["object"]["sha"]
    else
      tag_sha # Lightweight tag points directly to commit
    end

    # Get the tree SHA from the commit
    commit_response = self.class.get("/repos/#{repo_full_name}/git/commits/#{commit_sha}",
      headers: self.class.headers)

    if commit_response.success?
      commit_response.parsed_response["tree"]["sha"]
    end
  end

  def get_files_from_tree(repo_full_name, tree_sha, path = "")
    response = self.class.get("/repos/#{repo_full_name}/git/trees/#{tree_sha}?recursive=1",
      headers: self.class.headers)

    return [] unless response.success?

    files = []
    response.parsed_response["tree"].each do |item|
      if item["type"] == "blob"
        files << {
          path: item["path"],
          sha: item["sha"],
          size: item["size"]
        }
      end
    end

    files
  end

  def fetch_file_content(repo_full_name, file_path, tag_name)
    response = self.class.get("/repos/#{repo_full_name}/contents/#{file_path}?ref=#{tag_name}",
      headers: self.class.headers)

    if response.success?
      # Content is base64 encoded
      Base64.decode64(response.parsed_response["content"])
    else
      Rails.logger.error "[GithubVersionTagging] Failed to fetch file #{file_path}: #{response.code}"
      nil
    end
  end

  def skip_file?(path)
    # Skip files that shouldn't be restored
    skip_patterns = [
      /^\.git\//,
      /^\.github\/workflows\//,
      /^node_modules\//,
      /^dist\//,
      /^build\//,
      /\.map$/,
      /^\.env/
    ]

    skip_patterns.any? { |pattern| path.match?(pattern) }
  end

  def determine_file_type(path)
    case ::File.extname(path).downcase
    when ".tsx", ".ts"
      "typescript"
    when ".jsx", ".js"
      "javascript"
    when ".css", ".scss", ".sass"
      "css"
    when ".html"
      "html"
    when ".json"
      "json"
    when ".md"
      "markdown"
    when ".yml", ".yaml"
      "yaml"
    else
      "text"
    end
  end
end
