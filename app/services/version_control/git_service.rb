module VersionControl
  # Git integration service for version control operations
  # Provides AI with ability to manage code versions and track changes
  class GitService
    require "git"
    require "fileutils"

    def initialize(app)
      @app = app
      @repo_path = app_repo_path
      ensure_git_repo
    end

    # Initialize or get existing git repository
    def ensure_git_repo
      if File.exist?(File.join(@repo_path, ".git"))
        @git = Git.open(@repo_path)
      else
        FileUtils.mkdir_p(@repo_path) unless File.exist?(@repo_path)
        @git = Git.init(@repo_path)
        setup_initial_repo
      end
    rescue => e
      Rails.logger.error "[GitService] Failed to initialize repo: #{e.message}"
      nil
    end

    # Get current status of the repository
    def status
      return {success: false, error: "Git not initialized"} unless @git

      status_info = {
        current_branch: @git.current_branch,
        changed_files: [],
        untracked_files: [],
        staged_files: [],
        clean: true
      }

      # Get modified files
      @git.status.changed.each do |file, status|
        status_info[:changed_files] << {
          path: file,
          type: status.type,
          changes: get_file_diff(file)
        }
        status_info[:clean] = false
      end

      # Get untracked files
      @git.status.untracked.each do |file, _|
        status_info[:untracked_files] << file
        status_info[:clean] = false
      end

      # Get staged files
      @git.status.added.each do |file, _|
        status_info[:staged_files] << file
      end

      {
        success: true,
        status: status_info,
        message: status_info[:clean] ? "Working directory clean" : "Changes detected"
      }
    rescue => e
      Rails.logger.error "[GitService] Failed to get status: #{e.message}"
      {success: false, error: e.message}
    end

    # Create a new commit with AI-generated message
    def commit(message, author = nil)
      return {success: false, error: "Git not initialized"} unless @git

      # Stage all changes from app files
      sync_files_to_repo

      # Add all files to staging
      @git.add(all: true)

      # Check if there are changes to commit
      if @git.status.changed.empty? && @git.status.added.empty? && @git.status.deleted.empty?
        return {success: false, error: "No changes to commit"}
      end

      # Create commit
      commit_options = {
        message: format_commit_message(message),
        author: author || "OverSkill AI <ai@overskill.app>"
      }

      commit = @git.commit(commit_options[:message], commit_options)

      # Track commit in app metadata
      track_commit(commit)

      {
        success: true,
        commit_sha: commit.sha,
        message: commit.message,
        files_changed: commit.diff_parent.stats[:files].keys,
        stats: commit.diff_parent.stats[:total]
      }
    rescue => e
      Rails.logger.error "[GitService] Failed to commit: #{e.message}"
      {success: false, error: e.message}
    end

    # Create a new branch
    def create_branch(branch_name, checkout = true)
      return {success: false, error: "Git not initialized"} unless @git

      # Check if branch already exists
      if @git.branches.local.map(&:name).include?(branch_name)
        return {success: false, error: "Branch '#{branch_name}' already exists"}
      end

      # Create new branch
      @git.branch(branch_name).create

      # Checkout if requested
      @git.checkout(branch_name) if checkout

      {
        success: true,
        branch: branch_name,
        checked_out: checkout,
        message: "Created branch '#{branch_name}'"
      }
    rescue => e
      Rails.logger.error "[GitService] Failed to create branch: #{e.message}"
      {success: false, error: e.message}
    end

    # Switch to a different branch
    def checkout(branch_name)
      return {success: false, error: "Git not initialized"} unless @git

      # Check if branch exists
      unless @git.branches.local.map(&:name).include?(branch_name)
        return {success: false, error: "Branch '#{branch_name}' does not exist"}
      end

      # Checkout branch
      @git.checkout(branch_name)

      {
        success: true,
        branch: branch_name,
        message: "Switched to branch '#{branch_name}'"
      }
    rescue => e
      Rails.logger.error "[GitService] Failed to checkout: #{e.message}"
      {success: false, error: e.message}
    end

    # Get commit history
    def log(limit = 10, branch = nil)
      return {success: false, error: "Git not initialized"} unless @git

      branch ||= @git.current_branch
      commits = []

      @git.log(limit).each do |commit|
        files_changed = begin
          commit.diff_parent.stats[:files].keys
        rescue
          []
        end

        stats = begin
          commit.diff_parent.stats[:total]
        rescue
          {}
        end

        commits << {
          sha: commit.sha,
          message: commit.message,
          author: commit.author.name,
          date: commit.date.iso8601,
          files_changed: files_changed,
          stats: stats
        }
      end

      {
        success: true,
        branch: branch,
        commits: commits,
        total: commits.length
      }
    rescue => e
      Rails.logger.error "[GitService] Failed to get log: #{e.message}"
      {success: false, error: e.message}
    end

    # Get diff for a specific file or all changes
    def diff(file_path = nil, from_commit = nil, to_commit = nil)
      return {success: false, error: "Git not initialized"} unless @git

      diff_output = if from_commit && to_commit
        @git.diff(from_commit, to_commit)
      elsif from_commit
        @git.diff(from_commit, "HEAD")
      else
        @git.diff
      end

      # Filter by file if specified
      diff_output = diff_output.path(file_path) if file_path

      changes = []
      diff_output.each do |file_diff|
        changes << {
          path: file_diff.path,
          type: file_diff.type,
          insertions: file_diff.insertions,
          deletions: file_diff.deletions,
          patch: file_diff.patch
        }
      end

      {
        success: true,
        changes: changes,
        total_files: changes.length,
        total_insertions: changes.sum { |c| c[:insertions] },
        total_deletions: changes.sum { |c| c[:deletions] }
      }
    rescue => e
      Rails.logger.error "[GitService] Failed to get diff: #{e.message}"
      {success: false, error: e.message}
    end

    # Revert to a previous commit
    def revert(commit_sha)
      return {success: false, error: "Git not initialized"} unless @git

      # Find the commit
      commit = @git.log.find { |c| c.sha.start_with?(commit_sha) }
      return {success: false, error: "Commit not found: #{commit_sha}"} unless commit

      # Create a revert commit
      @git.revert(commit.sha)

      # Sync changes back to app files
      sync_repo_to_files

      {
        success: true,
        reverted_commit: commit.sha,
        message: "Reverted commit: #{commit.message}"
      }
    rescue => e
      Rails.logger.error "[GitService] Failed to revert: #{e.message}"
      {success: false, error: e.message}
    end

    # Reset to a specific commit (hard reset)
    def reset(commit_sha, mode = "hard")
      return {success: false, error: "Git not initialized"} unless @git

      # Find the commit
      commit = @git.log.find { |c| c.sha.start_with?(commit_sha) }
      return {success: false, error: "Commit not found: #{commit_sha}"} unless commit

      # Reset to commit
      @git.reset(commit.sha, mode)

      # Sync changes back to app files
      sync_repo_to_files

      {
        success: true,
        reset_to: commit.sha,
        mode: mode,
        message: "Reset to commit: #{commit.message}"
      }
    rescue => e
      Rails.logger.error "[GitService] Failed to reset: #{e.message}"
      {success: false, error: e.message}
    end

    # Stash current changes
    def stash(message = nil)
      return {success: false, error: "Git not initialized"} unless @git

      # Add all changes before stashing
      @git.add(all: true)

      # Create stash
      stash_result = if message
        @git.lib.send(:command, "stash", ["save", message])
      else
        @git.lib.send(:command, "stash")
      end

      {
        success: true,
        message: message || "Stashed changes",
        stash_id: stash_result
      }
    rescue => e
      Rails.logger.error "[GitService] Failed to stash: #{e.message}"
      {success: false, error: e.message}
    end

    # Apply stashed changes
    def stash_pop
      return {success: false, error: "Git not initialized"} unless @git

      @git.lib.send(:command, "stash", ["pop"])

      # Sync changes back to app files
      sync_repo_to_files

      {
        success: true,
        message: "Applied stashed changes"
      }
    rescue => e
      Rails.logger.error "[GitService] Failed to pop stash: #{e.message}"
      {success: false, error: e.message}
    end

    # List all branches
    def branches
      return {success: false, error: "Git not initialized"} unless @git

      local_branches = @git.branches.local.map do |branch|
        last_commit = begin
          branch.gcommit.sha
        rescue
          nil
        end

        last_commit_message = begin
          branch.gcommit.message
        rescue
          nil
        end

        {
          name: branch.name,
          current: branch.name == @git.current_branch,
          last_commit: last_commit,
          last_commit_message: last_commit_message
        }
      end

      {
        success: true,
        current_branch: @git.current_branch,
        branches: local_branches,
        total: local_branches.length
      }
    rescue => e
      Rails.logger.error "[GitService] Failed to list branches: #{e.message}"
      {success: false, error: e.message}
    end

    # Merge branches
    def merge(source_branch, message = nil)
      return {success: false, error: "Git not initialized"} unless @git

      # Check if branch exists
      unless @git.branches.local.map(&:name).include?(source_branch)
        return {success: false, error: "Branch '#{source_branch}' does not exist"}
      end

      # Get current branch
      target_branch = @git.current_branch

      # Perform merge
      @git.merge(source_branch, message || "Merge branch '#{source_branch}' into #{target_branch}")

      # Sync changes back to app files
      sync_repo_to_files

      {
        success: true,
        source_branch: source_branch,
        target_branch: target_branch,
        message: "Merged '#{source_branch}' into '#{target_branch}'"
      }
    rescue Git::GitExecuteError => e
      if e.message.include?("conflict")
        {success: false, error: "Merge conflict detected", conflicts: get_conflicts}
      else
        {success: false, error: e.message}
      end
    rescue => e
      Rails.logger.error "[GitService] Failed to merge: #{e.message}"
      {success: false, error: e.message}
    end

    # Tag a specific commit
    def tag(tag_name, message = nil, commit_sha = nil)
      return {success: false, error: "Git not initialized"} unless @git

      # Check if tag already exists
      if @git.tags.map(&:name).include?(tag_name)
        return {success: false, error: "Tag '#{tag_name}' already exists"}
      end

      # Create tag
      tag_options = {name: tag_name}
      tag_options[:message] = message if message
      tag_options[:commit] = commit_sha if commit_sha

      @git.add_tag(tag_name, tag_options)

      {
        success: true,
        tag: tag_name,
        message: message || "Created tag '#{tag_name}'",
        commit: commit_sha || @git.log.first.sha
      }
    rescue => e
      Rails.logger.error "[GitService] Failed to tag: #{e.message}"
      {success: false, error: e.message}
    end

    private

    def app_repo_path
      Rails.root.join("tmp", "repos", "app_#{@app.id}")
    end

    def setup_initial_repo
      # Create initial .gitignore
      File.write(File.join(@repo_path, ".gitignore"), default_gitignore)

      # Create README
      File.write(File.join(@repo_path, "README.md"), initial_readme)

      # Initial commit
      @git.add(all: true)
      @git.commit("Initial commit - OverSkill AI generated app")
    end

    def sync_files_to_repo
      # Copy all app files to git repository
      @app.app_files.each do |file|
        file_path = File.join(@repo_path, file.path)
        FileUtils.mkdir_p(File.dirname(file_path))

        if file.is_binary?
          # Decode base64 for binary files
          File.binwrite(file_path, Base64.decode64(file.content))
        else
          File.write(file_path, file.content)
        end
      end
    end

    def sync_repo_to_files
      # Copy git repository files back to app files
      Dir.glob(File.join(@repo_path, "**", "*")).each do |file_path|
        next if File.directory?(file_path)
        next if file_path.include?(".git/")

        relative_path = file_path.sub(@repo_path.to_s + "/", "")

        app_file = @app.app_files.find_or_initialize_by(path: relative_path)

        if binary_file?(file_path)
          app_file.content = Base64.encode64(File.binread(file_path))
          app_file.is_binary = true
        else
          app_file.content = File.read(file_path)
          app_file.is_binary = false
        end

        app_file.file_type = detect_file_type(relative_path)
        app_file.team = @app.team if app_file.new_record?
        app_file.save!
      end
    end

    def get_file_diff(file_path)
      @git.diff.path(file_path).to_s
    rescue
      ""
    end

    def track_commit(commit)
      # Store commit info in app metadata
      commits = JSON.parse(@app.metadata || "{}")["git_commits"] || []
      commits.unshift({
        sha: commit.sha,
        message: commit.message,
        date: commit.date.iso8601,
        author: commit.author.name
      })
      commits = commits.first(50) # Keep last 50 commits

      @app.update_column(:metadata, @app.metadata.to_h.merge(git_commits: commits).to_json)
    end

    def format_commit_message(message)
      # Add AI-generated prefix if not present
      unless message.start_with?("[AI]")
        message = "[AI] #{message}"
      end

      # Add timestamp
      "#{message}\n\nGenerated at: #{Time.current.iso8601}"
    end

    def get_conflicts
      conflicts = []
      @git.status.unmerged.each do |file, _|
        conflicts << file
      end
      conflicts
    end

    def binary_file?(file_path)
      # Check if file is binary based on extension
      binary_extensions = %w[.png .jpg .jpeg .gif .ico .pdf .zip .tar .gz]
      binary_extensions.any? { |ext| file_path.downcase.end_with?(ext) }
    end

    def detect_file_type(path)
      extension = File.extname(path).downcase

      case extension
      when ".html" then "html"
      when ".css" then "css"
      when ".js", ".jsx" then "js"
      when ".ts", ".tsx" then "typescript"
      when ".json" then "json"
      when ".md" then "markdown"
      else "text"
      end
    end

    def default_gitignore
      <<~GITIGNORE
        # Dependencies
        node_modules/
        .pnp
        .pnp.js
        
        # Testing
        coverage/
        
        # Production
        build/
        dist/
        
        # Misc
        .DS_Store
        .env.local
        .env.development.local
        .env.test.local
        .env.production.local
        
        # Logs
        npm-debug.log*
        yarn-debug.log*
        yarn-error.log*
        
        # IDE
        .idea/
        .vscode/
        *.swp
        *.swo
      GITIGNORE
    end

    def initial_readme
      <<~README
        # #{@app.name}
        
        Generated by OverSkill AI App Builder
        
        ## Description
        #{@app.description || "AI-generated application"}
        
        ## Type
        #{@app.app_type}
        
        ## Framework
        #{@app.framework}
        
        ## Generated
        #{Time.current.strftime("%B %d, %Y")}
        
        ---
        Built with ❤️ by OverSkill
      README
    end
  end
end
