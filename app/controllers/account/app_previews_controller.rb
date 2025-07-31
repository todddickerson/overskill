class Account::AppPreviewsController < Account::ApplicationController
  skip_before_action :verify_authenticity_token, only: [:serve_file]
  before_action :set_app
  
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
    file = @app.app_files.find_by(path: params[:path])
    
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
      render plain: file.content, layout: false
    else
      render plain: "File not found", status: :not_found
    end
  end
  
  private
  
  def set_app
    @app = current_team.apps.find(params[:app_id])
  end
  
  def process_html_for_preview(html)
    # Replace relative asset paths with our preview routes
    html = html.dup
    
    # Replace script src references
    html.gsub!(/src=["']([^"']+\.js)["']/) do |match|
      src = $1
      %Q{src="#{file_account_app_preview_path(@app, path: src)}"}
    end
    
    # Replace link href references for CSS
    html.gsub!(/href=["']([^"']+\.css)["']/) do |match|
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