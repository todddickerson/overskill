class Account::AppPreviewsController < Account::ApplicationController
  skip_before_action :verify_authenticity_token, only: [:serve_file]
  skip_before_action :authenticate_user!, only: [:serve_file]
  skip_before_action :ensure_onboarding_is_complete_and_set_next_step, only: [:serve_file]
  before_action :set_app
  before_action :set_permissive_csp

  def show
    # Get the requested page from params, default to index.html
    requested_page = params[:page] || "index.html"

    # Find the HTML file by path
    @html_file = @app.app_files.find_by(path: requested_page, file_type: "html")

    # Fall back to any HTML file if specific page not found
    @html_file ||= @app.app_files.find_by(path: "index.html", file_type: "html")
    @html_file ||= @app.app_files.find_by(file_type: "html")

    if @html_file
      render html: process_html_for_preview(@html_file.content).html_safe
    else
      render plain: "No HTML file found", status: :not_found
    end
  end

  def serve_file
    path = params[:path]

    # Strip query parameters from the path
    path = path.split("?").first if path.include?("?")

    # Handle external URLs (CDN links)
    if path.start_with?("http://", "https://")
      redirect_to path, allow_other_host: true
      return
    end

    # Special handling for overskill.js - serve from Rails public directory
    if path == "overskill.js"
      overskill_path = Rails.root.join("public", "overskill.js")
      if File.exist?(overskill_path)
        response.headers["Content-Type"] = "application/javascript"
        response.headers["Cache-Control"] = "no-cache"
        send_file overskill_path, type: "application/javascript", disposition: "inline"
        return
      end
    end

    file = @app.app_files.find_by(path: path)

    if file
      content_type = case file.file_type
      when "javascript" then "application/javascript"
      when "css" then "text/css"
      when "json" then "application/json"
      when "html" then "text/html"
      else "text/plain"
      end

      # Set proper headers for the content type
      response.headers["Content-Type"] = content_type
      response.headers["Cache-Control"] = "no-cache"

      # Use send_data instead of render plain to ensure proper content type handling
      send_data file.content, type: content_type, disposition: "inline"
    else
      render plain: "File not found: #{path}", status: :not_found
    end
  end

  private

  def set_app
    # For serve_file action, we need to find the app without authentication
    @app = if action_name == "serve_file"
      # Use the obfuscated ID to find the app directly
      App.find(params[:app_id])
    else
      # For authenticated actions, use the team scope
      current_team.apps.find(params[:app_id])
    end
  end

  def set_permissive_csp
    # Completely disable CSP to avoid any restrictions on generated apps
    # This removes all Content Security Policy restrictions
    response.headers.delete("Content-Security-Policy")
    response.headers.delete("Content-Security-Policy-Report-Only")

    # Also disable X-Frame-Options to allow embedding
    response.headers["X-Frame-Options"] = "ALLOWALL"
  end

  def process_html_for_preview(html)
    # Replace relative asset paths with our preview routes
    html = html.dup

    # Replace script src references (including those with query params)
    html.gsub!(/src=["']([^"']+\.js(?:\?[^"']*)?)["']/) do |match|
      src = $1
      # Skip external URLs
      next match if src.start_with?("http://", "https://", "//")
      %(src="#{file_account_app_preview_path(@app, path: src)}")
    end

    # Replace link href references for CSS (including those with query params)
    html.gsub!(/href=["']([^"']+\.css(?:\?[^"']*)?)["']/) do |match|
      href = $1
      # Skip external URLs
      next match if href.start_with?("http://", "https://", "//")
      %(href="#{file_account_app_preview_path(@app, path: href)}")
    end

    # Add base tag to handle relative URLs
    if html.include?("<head>")
      base_tag = %(<base href="#{account_app_preview_path(@app)}/">)
      html.gsub!("<head>", "<head>\n#{base_tag}")
    end

    html
  end
end
