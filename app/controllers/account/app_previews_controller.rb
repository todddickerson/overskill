class Account::AppPreviewsController < Account::ApplicationController
  skip_before_action :verify_authenticity_token, only: [:serve_file]
  before_action :set_app
  before_action :set_permissive_csp
  
  def show
    # Serve the main HTML file or index.html
    # TODO: Serve from Cloudflare Workers w/ real NodeJS app
    @html_file = @app.app_files.find_by(file_type: "html") || @app.app_files.find_by(path: "index.html")
    
    if @html_file
      render html: process_html_for_preview(@html_file.content).html_safe
    else
      render plain: "No HTML file found", status: :not_found
    end
  end
  
  def serve_file
    path = params[:path]
    
    # Strip query parameters from the path
    path = path.split('?').first if path.include?('?')
    
    # Handle external URLs (CDN links)
    if path.start_with?('http://') || path.start_with?('https://')
      redirect_to path, allow_other_host: true
      return
    end
    
    # Special handling for overskill.js - serve from Rails public directory
    if path == 'overskill.js'
      overskill_path = Rails.root.join('public', 'overskill.js')
      if File.exist?(overskill_path)
        response.headers['Content-Type'] = 'application/javascript'
        response.headers['Cache-Control'] = 'no-cache'
        send_file overskill_path, type: 'application/javascript', disposition: 'inline'
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
      response.headers['Content-Type'] = content_type
      response.headers['Cache-Control'] = 'no-cache'
      
      # Use send_data instead of render plain to ensure proper content type handling
      send_data file.content, type: content_type, disposition: 'inline'
    else
      render plain: "File not found: #{path}", status: :not_found
    end
  end
  
  private
  
  def set_app
    @app = current_team.apps.find(params[:app_id])
  end
  
  def set_permissive_csp
    # Set very permissive CSP for generated app content
    # This allows inline styles and scripts which are common in generated apps
    csp_header = [
      "default-src 'self' 'unsafe-inline' 'unsafe-eval' https: data: blob:",
      "script-src 'self' 'unsafe-inline' 'unsafe-eval' https: data: blob:",
      "style-src 'self' 'unsafe-inline' https: data:",
      "font-src 'self' https: data:",
      "img-src 'self' https: data: blob:",
      "connect-src 'self' https: wss: ws: data:",
      "frame-src 'self' https:",
      "object-src 'none'",
      "media-src 'self' https: data: blob:",
      "worker-src 'self' blob:"
    ].join('; ')
    
    response.headers['Content-Security-Policy'] = csp_header
  end
  
  def process_html_for_preview(html)
    # Replace relative asset paths with our preview routes
    html = html.dup
    
    # Replace script src references (including those with query params)
    html.gsub!(/src=["']([^"']+\.js(?:\?[^"']*)?)["']/) do |match|
      src = $1
      %Q{src="#{file_account_app_preview_path(@app, path: src)}"}
    end
    
    # Replace link href references for CSS (including those with query params)
    html.gsub!(/href=["']([^"']+\.css(?:\?[^"']*)?)["']/) do |match|
      href = $1
      %Q{href="#{file_account_app_preview_path(@app, path: href)}"}
    end
    
    # Add base tag to handle relative URLs
    if html.include?("<head>")
      base_tag = %Q{<base href="#{account_app_preview_path(@app)}/">}
      html.gsub!("<head>", "<head>\n#{base_tag}")
    end
    
    html
  end
end