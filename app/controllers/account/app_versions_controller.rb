class Account::AppVersionsController < Account::ApplicationController
  account_load_and_authorize_resource :app_version, through: :app, through_association: :app_versions

  # For member actions, load the app_version directly
  before_action :load_app_version, only: [:preview, :serve_file, :compare, :bookmark, :restore]

  # GET /account/apps/:app_id/app_versions
  # GET /account/apps/:app_id/app_versions.json
  def index
    delegate_json_to_api
  end

  # GET /account/app_versions/:id
  # GET /account/app_versions/:id.json
  def show
    respond_to do |format|
      format.html
      format.json do
        render json: {
          id: @app_version.id,
          version_number: @app_version.version_number,
          changelog: @app_version.changelog,
          created_at: @app_version.created_at,
          is_latest: @app_version == @app_version.app.app_versions.order(created_at: :desc).first,
          files_count: @app_version.app_version_files.count
        }
      end
    end
  end

  # GET /account/apps/:app_id/app_versions/new
  def new
  end

  # GET /account/app_versions/:id/edit
  def edit
  end

  # POST /account/apps/:app_id/app_versions
  # POST /account/apps/:app_id/app_versions.json
  def create
    respond_to do |format|
      if @app_version.save
        format.html { redirect_to [:account, @app_version], notice: I18n.t("app_versions.notifications.created") }
        format.json { render :show, status: :created, location: [:account, @app_version] }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @app_version.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /account/app_versions/:id
  # PATCH/PUT /account/app_versions/:id.json
  def update
    respond_to do |format|
      if @app_version.update(app_version_params)
        format.html { redirect_to [:account, @app_version], notice: I18n.t("app_versions.notifications.updated") }
        format.json { render :show, status: :ok, location: [:account, @app_version] }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @app_version.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /account/app_versions/:id
  # DELETE /account/app_versions/:id.json
  def destroy
    @app_version.destroy
    respond_to do |format|
      format.html { redirect_to [:account, @app, :app_versions], notice: I18n.t("app_versions.notifications.destroyed") }
      format.json { head :no_content }
    end
  end

  # GET /account/app_versions/:id/preview
  def preview
    app = @app_version.app

    # If this is the latest version and the app has a preview URL from fast deployment, redirect to it
    latest_version = app.app_versions.order(created_at: :desc).first
    if @app_version == latest_version && app.preview_url.present?
      Rails.logger.info "[Preview] Redirecting to fast deployment preview: #{app.preview_url}"
      redirect_to app.preview_url, allow_other_host: true
      return
    end

    # For V5, we need to temporarily restore the version's files, build, and deploy
    begin
      Rails.logger.info "[Preview] Starting preview for version #{@app_version.version_number}"

      # Save current files state to restore later
      original_files = app.app_files.map do |file|
        {
          path: file.path,
          content: file.content,
          file_type: file.file_type,
          size_bytes: file.size_bytes,
          is_entry_point: file.is_entry_point
        }
      end

      # Temporarily restore version's files
      files_restored = false

      if @app_version.files_snapshot.present?
        # V5 versions with snapshot
        snapshot_files = JSON.parse(@app_version.files_snapshot)
        app.app_files.destroy_all

        snapshot_files.each do |file_data|
          app.app_files.create!(
            team: app.team,
            path: file_data["path"],
            content: file_data["content"],
            file_type: file_data["file_type"] || determine_file_type(file_data["path"]),
            size_bytes: file_data["content"].bytesize,
            is_entry_point: (file_data["path"] == "index.html")
          )
        end
        files_restored = true

      elsif @app_version.app_version_files.any?
        # Older versions with app_version_files
        app.app_files.destroy_all

        @app_version.app_version_files.includes(:app_file).each do |version_file|
          next if version_file.action == "deleted"
          original_file = version_file.app_file

          app.app_files.create!(
            team: app.team,
            path: original_file.path,
            content: version_file.content || original_file.content,
            file_type: original_file.file_type,
            size_bytes: (version_file.content || original_file.content).bytesize,
            is_entry_point: original_file.is_entry_point
          )
        end
        files_restored = true
      end

      if !files_restored
        Rails.logger.error "[Preview] No files to preview for version #{@app_version.version_number}"
        redirect_to [:account, app, :editor],
          alert: "This version has no files to preview"
        return
      end

      # Build and deploy the version
      builder = Deployment::ExternalViteBuilder.new(app)
      build_result = builder.build_for_preview_with_r2

      if build_result[:success]
        deployer = Deployment::CloudflareWorkersDeployer.new(app)

        # Deploy to a version-specific preview worker
        deploy_result = deployer.deploy_with_secrets(
          built_code: build_result[:built_code],
          r2_asset_urls: build_result[:r2_asset_urls],
          deployment_type: :preview,
          worker_name_override: "version-#{@app_version.id}-#{app.id}"
        )

        app.app_files.destroy_all
        original_files.each do |file_data|
          app.app_files.create!(
            team: app.team,
            path: file_data[:path],
            content: file_data[:content],
            file_type: file_data[:file_type],
            size_bytes: file_data[:size_bytes],
            is_entry_point: file_data[:is_entry_point]
          )
        end
        if deploy_result[:success]
          # Restore original files

          # Redirect to the preview URL
          preview_url = deploy_result[:worker_url] || deploy_result[:deployment_url]
          Rails.logger.info "[Preview] Successfully deployed version preview to #{preview_url}"
          redirect_to preview_url, allow_other_host: true
        else
          # Restore original files

          redirect_to [:account, app, :editor],
            alert: "Failed to deploy preview: #{deploy_result[:error]}"
        end
      else
        # Restore original files
        app.app_files.destroy_all
        original_files.each do |file_data|
          app.app_files.create!(
            team: app.team,
            path: file_data[:path],
            content: file_data[:content],
            file_type: file_data[:file_type],
            size_bytes: file_data[:size_bytes],
            is_entry_point: file_data[:is_entry_point]
          )
        end

        redirect_to [:account, app, :editor],
          alert: "Failed to build preview: #{build_result[:error]}"
      end
    rescue => e
      Rails.logger.error "[Preview] Failed to preview version: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      # Try to restore original files if something went wrong
      if defined?(original_files) && original_files
        app.app_files.destroy_all
        original_files.each do |file_data|
          app.app_files.create!(
            team: app.team,
            path: file_data[:path],
            content: file_data[:content],
            file_type: file_data[:file_type],
            size_bytes: file_data[:size_bytes],
            is_entry_point: file_data[:is_entry_point]
          )
        rescue
          nil
        end
      end

      redirect_to [:account, app, :editor],
        alert: "Failed to preview version: #{e.message}"
    end
  end

  # GET /account/app_versions/:id/files/*path
  def serve_file
    path = params[:path]

    # Find the version file by path
    version_file = @app_version.app_version_files
      .joins(:app_file)
      .find_by(app_files: {path: path})

    if version_file
      app_file = version_file.app_file
      content_type = case app_file.file_type
      when "javascript" then "application/javascript"
      when "css" then "text/css"
      when "json" then "application/json"
      when "html" then "text/html"
      else "text/plain"
      end

      # Set proper headers for the content type
      response.headers["Content-Type"] = content_type
      response.headers["Cache-Control"] = "no-cache"

      # Use the version-specific content
      send_data version_file.content, type: content_type, disposition: "inline"
    else
      render plain: "File not found in this version", status: :not_found
    end
  end

  # GET /account/app_versions/:id/compare
  def compare
    # Find the previous version to compare against
    @previous_version = @app_version.app.app_versions
      .where("created_at < ?", @app_version.created_at)
      .order(created_at: :desc)
      .first

    file_changes = generate_file_diff(@previous_version, @app_version)

    @comparison = {
      current_version: @app_version.version_number,
      previous_version: @previous_version&.version_number || "Initial",
      file_changes: file_changes,
      total_additions: file_changes.sum { |fc| fc[:additions] || 0 },
      total_deletions: file_changes.sum { |fc| fc[:deletions] || 0 },
      files_changed: file_changes.count
    }

    respond_to do |format|
      format.html
      format.json { render json: @comparison }
    end
  end

  # POST /account/app_versions/:id/bookmark
  def bookmark
    @app_version.toggle!(:bookmarked)

    respond_to do |format|
      format.json { render json: {bookmarked: @app_version.bookmarked?} }
    end
  end

  # POST /account/app_versions/:id/restore
  def restore
    app = @app_version.app

    # Use the new restoration service for consistent restoration
    restoration_service = Deployment::AppVersionRestorationService.new(app)
    result = restoration_service.restore_to_version(
      @app_version,
      auto_deploy: false,
      sync_to_github: true
    )

    if result[:success]
      # Update the preview deployment
      UpdatePreviewJob.perform_later(app.id)

      respond_to do |format|
        format.json {
          render json: {
            success: true,
            new_version_id: result[:version]&.id,
            files_restored: result[:restored_count],
            message: result[:message] || "Successfully restored from version #{@app_version.version_number}"
          }
        }
      end
    else
      respond_to do |format|
        format.json {
          render json: {
            success: false,
            error: result[:error] || "Failed to restore version",
            failed_files: result[:failed_files]
          }, status: :unprocessable_entity
        }
      end
    end

    return  # Exit early since we've handled all cases

    # Old code below is now replaced by the restoration service
    respond_to do |format|
      format.json { render json: {success: false, errors: new_version.errors.full_messages}, status: :unprocessable_entity }
    end
  end

  private

  def load_app_version
    @app_version ||= AppVersion.joins(app: :team).where(apps: {team_id: current_team.id}).find(params[:id])
    @app ||= @app_version.app
  end

  if defined?(Api::V1::ApplicationController)
    include strong_parameters_from_api
  end

  def process_params(strong_params)
    assign_date_and_time(strong_params, :published_at)
    # 🚅 super scaffolding will insert processing for new fields above this line.
  end

  def generate_file_diff(previous_version, current_version)
    file_changes = []

    # Get all files from both versions
    current_files = current_version.app_version_files.includes(:app_file).index_by { |vf| vf.app_file.path }
    previous_files = previous_version&.app_version_files&.includes(:app_file)&.index_by { |vf| vf.app_file.path } || {}

    # Check files in current version
    current_files.each do |path, current_file|
      previous_file = previous_files[path]

      if previous_file.nil?
        # New file
        file_changes << {
          path: path,
          status: "created",
          additions: count_lines(current_file.content),
          deletions: 0,
          diff: generate_creation_diff(current_file.content)
        }
      elsif previous_file.content != current_file.content
        # Modified file
        diff_result = generate_unified_diff(previous_file.content, current_file.content, path)
        file_changes << {
          path: path,
          status: "updated",
          additions: diff_result[:additions],
          deletions: diff_result[:deletions],
          diff: diff_result[:diff]
        }
      end
    end

    # Check for deleted files
    previous_files.each do |path, previous_file|
      unless current_files.key?(path)
        file_changes << {
          path: path,
          status: "deleted",
          additions: 0,
          deletions: count_lines(previous_file.content),
          diff: generate_deletion_diff(previous_file.content)
        }
      end
    end

    file_changes
  end

  def generate_unified_diff(old_content, new_content, filename)
    old_lines = old_content.split("\n")
    new_lines = new_content.split("\n")

    # Simple line-by-line diff
    diff_lines = []
    additions = 0
    deletions = 0

    # Add file header
    diff_lines << "@@ -1,#{old_lines.length} +1,#{new_lines.length} @@"

    # Very basic diff - show all lines for now
    # In a real implementation, you'd use a proper diff algorithm like Myers
    max_lines = [old_lines.length, new_lines.length].max

    (0...max_lines).each do |i|
      old_line = old_lines[i]
      new_line = new_lines[i]

      if old_line && new_line
        if old_line != new_line
          diff_lines << "-#{old_line}"
          diff_lines << "+#{new_line}"
          deletions += 1
          additions += 1
        else
          diff_lines << " #{old_line}"
        end
      elsif old_line
        diff_lines << "-#{old_line}"
        deletions += 1
      elsif new_line
        diff_lines << "+#{new_line}"
        additions += 1
      end
    end

    {
      diff: diff_lines.join("\n"),
      additions: additions,
      deletions: deletions
    }
  end

  def generate_creation_diff(content)
    lines = content.split("\n")
    diff_lines = ["@@ -0,0 +1,#{lines.length} @@"]
    lines.each { |line| diff_lines << "+#{line}" }
    diff_lines.join("\n")
  end

  def generate_deletion_diff(content)
    lines = content.split("\n")
    diff_lines = ["@@ -1,#{lines.length} +0,0 @@"]
    lines.each { |line| diff_lines << "-#{line}" }
    diff_lines.join("\n")
  end

  def count_lines(content)
    content.split("\n").length
  end

  def compare_versions(version1, version2)
    return {} unless version1 && version2

    {
      version_numbers: {
        from: version2.version_number,
        to: version1.version_number
      },
      changelog: {
        from: version2.changelog,
        to: version1.changelog
      },
      created_at: {
        from: version2.created_at,
        to: version1.created_at
      },
      time_difference: time_ago_in_words(version2.created_at)
    }
  end

  def next_version_number(app)
    last_version = app.app_versions.order(created_at: :desc).first
    if last_version
      # Handle both "v1.0.0" and "1.0.0" formats
      version_str = last_version.version_number.gsub(/^v/, "")
      parts = version_str.split(".")

      # Ensure we have 3 parts (major.minor.patch)
      parts = (parts + ["0", "0", "0"]).first(3)

      # Increment patch version
      parts[-1] = (parts[-1].to_i + 1).to_s

      # Preserve "v" prefix if the last version had it
      if last_version.version_number.start_with?("v")
        "v#{parts.join(".")}"
      else
        parts.join(".")
      end
    else
      "v1.0.0"  # Default to v-prefixed for new apps (V5 standard)
    end
  end

  def find_version_file(version, file_type)
    version.app_version_files
      .joins(:app_file)
      .find_by(app_files: {file_type: file_type}) ||
      version.app_version_files
        .joins(:app_file)
        .find_by(app_files: {path: "index.html"})
  end

  def process_html_for_version_preview(html)
    # Replace relative asset paths with version-specific routes
    html = html.dup

    # Replace script src references
    html.gsub!(/src=["']([^"']+\.js)["']/) do |match|
      src = $1
      %(src="#{file_account_app_version_path(@app_version, path: src)}")
    end

    # Replace link href references for CSS
    html.gsub!(/href=["']([^"']+\.css)["']/) do |match|
      href = $1
      %(href="#{file_account_app_version_path(@app_version, path: href)}")
    end

    html
  end

  def determine_file_type(path)
    case File.extname(path).downcase
    when ".js", ".jsx", ".ts", ".tsx"
      "javascript"
    when ".css", ".scss", ".sass", ".less"
      "css"
    when ".html", ".htm"
      "html"
    when ".json"
      "json"
    when ".md", ".markdown"
      "markdown"
    when ".yml", ".yaml"
      "yaml"
    when ".env"
      "env"
    else
      "other"
    end
  end
end
