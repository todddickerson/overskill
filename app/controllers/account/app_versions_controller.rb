class Account::AppVersionsController < Account::ApplicationController
  account_load_and_authorize_resource :app_version, through: :app, through_association: :app_versions

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
    # Deploy this specific version to a preview Worker
    service = Deployment::AppVersionPreviewService.new(@app_version)
    result = service.deploy_version_preview!
    
    if result[:success]
      redirect_to result[:preview_url], allow_other_host: true
    else
      redirect_to [:account, @app_version.app, :editor], 
                  alert: "Failed to preview version: #{result[:error]}"
    end
  end
  
  # GET /account/app_versions/:id/files/*path
  def serve_file
    path = params[:path]
    
    # Find the version file by path
    version_file = @app_version.app_version_files
                               .joins(:app_file)
                               .find_by(app_files: { path: path })
    
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
      response.headers['Content-Type'] = content_type
      response.headers['Cache-Control'] = 'no-cache'
      
      # Use the version-specific content
      send_data version_file.content, type: content_type, disposition: 'inline'
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
      format.json { render json: { bookmarked: @app_version.bookmarked? } }
    end
  end
  
  # POST /account/app_versions/:id/restore
  def restore
    app = @app_version.app
    
    # Create a new version with the content from this version
    new_version = app.app_versions.build(
      team: app.team,
      user: current_user,
      version_number: next_version_number(app),
      changelog: "Restored from version #{@app_version.version_number}"
    )
    
    if new_version.save
      # Copy all files from the old version to the new version
      @app_version.app_version_files.each do |version_file|
        app_file = version_file.app_file
        
        # Update the app file with the content from this version
        app_file.update!(
          content: version_file.content,
          size_bytes: version_file.content.bytesize
        )
        
        # Create a new version file record
        new_version.app_version_files.create!(
          app_file: app_file,
          content: version_file.content,
          action: "restored"
        )
      end
      
      # Update the preview deployment
      UpdatePreviewJob.perform_later(app.id)
      
      respond_to do |format|
        format.json { render json: { success: true, new_version_id: new_version.id } }
      end
    else
      respond_to do |format|
        format.json { render json: { success: false, errors: new_version.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  private

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
          status: 'created',
          additions: count_lines(current_file.content),
          deletions: 0,
          diff: generate_creation_diff(current_file.content)
        }
      elsif previous_file.content != current_file.content
        # Modified file
        diff_result = generate_unified_diff(previous_file.content, current_file.content, path)
        file_changes << {
          path: path,
          status: 'updated',
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
          status: 'deleted',
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
      parts = last_version.version_number.split(".")
      parts[-1] = (parts[-1].to_i + 1).to_s
      parts.join(".")
    else
      "1.0.0"
    end
  end
  
  def find_version_file(version, file_type)
    version.app_version_files
           .joins(:app_file)
           .find_by(app_files: { file_type: file_type }) ||
    version.app_version_files
           .joins(:app_file)
           .find_by(app_files: { path: "index.html" })
  end
  
  def process_html_for_version_preview(html)
    # Replace relative asset paths with version-specific routes
    html = html.dup
    
    # Replace script src references
    html.gsub!(/src=["']([^"']+\.js)["']/) do |match|
      src = $1
      %Q{src="#{file_account_app_version_path(@app_version, path: src)}"}
    end
    
    # Replace link href references for CSS
    html.gsub!(/href=["']([^"']+\.css)["']/) do |match|
      href = $1
      %Q{href="#{file_account_app_version_path(@app_version, path: href)}"}
    end
    
    html
  end
end
