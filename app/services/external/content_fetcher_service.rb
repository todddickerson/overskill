module External
  # Content fetching service for web search and file downloads
  # Similar to Lovable's web_search and lov-download-to-repo tools
  class ContentFetcherService
    require 'net/http'
    require 'uri'
    require 'open-uri'
    
    MAX_DOWNLOAD_SIZE = 10.megabytes
    ALLOWED_IMAGE_TYPES = %w[.jpg .jpeg .png .gif .svg .webp .ico].freeze
    ALLOWED_ASSET_TYPES = %w[.css .js .json .xml .txt .md].freeze
    
    def initialize(app)
      @app = app
    end

    # Web search functionality (similar to Lovable's web_search tool)
    def web_search(query, num_results: 5, category: nil)
      # In production, this would integrate with a search API like Google Custom Search, Bing, or Serper
      # For now, we'll implement a mock that shows the structure
      
      Rails.logger.info "[ContentFetcher] Performing web search for: #{query}"
      
      # This would be replaced with actual API call
      mock_search_results = generate_mock_results(query, num_results, category)
      
      {
        success: true,
        query: query,
        category: category,
        results: mock_search_results,
        total_results: mock_search_results.length
      }
    rescue => e
      Rails.logger.error "[ContentFetcher] Search failed: #{e.message}"
      { success: false, error: e.message }
    end

    # Download file from URL to project (similar to Lovable's lov-download-to-repo)
    def download_to_repo(source_url, target_path)
      # Validate URL
      uri = URI.parse(source_url)
      unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
        return { success: false, error: "Invalid URL: must be HTTP or HTTPS" }
      end
      
      # Validate target path
      file_extension = File.extname(target_path).downcase
      unless ALLOWED_IMAGE_TYPES.include?(file_extension) || ALLOWED_ASSET_TYPES.include?(file_extension)
        return { success: false, error: "Unsupported file type: #{file_extension}" }
      end
      
      # Determine if this should go in assets folder
      if ALLOWED_IMAGE_TYPES.include?(file_extension)
        # Images should go in src/assets for ES6 imports
        target_path = ensure_assets_path(target_path)
      end
      
      Rails.logger.info "[ContentFetcher] Downloading #{source_url} to #{target_path}"
      
      # Download the file
      downloaded_content = download_file(source_url)
      
      if downloaded_content[:success]
        # Save to app files
        file = @app.app_files.find_or_initialize_by(path: target_path)
        
        # For binary files (images), encode as base64
        if ALLOWED_IMAGE_TYPES.include?(file_extension)
          file.content = Base64.encode64(downloaded_content[:content])
          file.is_binary = true
        else
          file.content = downloaded_content[:content]
          file.is_binary = false
        end
        
        file.file_type = detect_file_type(target_path)
        file.size_bytes = downloaded_content[:size]
        file.team = @app.team if file.new_record?
        
        if file.save
          Rails.logger.info "[ContentFetcher] Successfully saved #{target_path} (#{file.size_bytes} bytes)"
          
          # Clear cache since we added a file
          Ai::ContextCacheService.new.clear_app_cache(@app.id)
          
          {
            success: true,
            target_path: target_path,
            size: file.size_bytes,
            file_type: file.file_type,
            message: "Downloaded and saved #{File.basename(target_path)}"
          }
        else
          { success: false, error: "Failed to save file: #{file.errors.full_messages.join(', ')}" }
        end
      else
        downloaded_content
      end
    rescue => e
      Rails.logger.error "[ContentFetcher] Download failed: #{e.message}"
      { success: false, error: e.message }
    end

    # Fetch website content in various formats (similar to Lovable's lov-fetch-website)
    def fetch_website(url, formats: ['markdown'])
      uri = URI.parse(url)
      unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
        return { success: false, error: "Invalid URL: must be HTTP or HTTPS" }
      end
      
      Rails.logger.info "[ContentFetcher] Fetching website content from #{url}"
      
      results = {}
      temp_dir = "tmp/fetched-websites/#{SecureRandom.hex(8)}"
      FileUtils.mkdir_p(Rails.root.join(temp_dir))
      
      formats.each do |format|
        case format.downcase
        when 'markdown'
          content = fetch_as_markdown(url)
          if content[:success]
            file_path = Rails.root.join(temp_dir, "content.md")
            File.write(file_path, content[:content])
            results[:markdown] = {
              path: file_path.to_s,
              preview: content[:content][0..500],
              size: content[:content].length
            }
          end
        when 'html'
          content = fetch_as_html(url)
          if content[:success]
            file_path = Rails.root.join(temp_dir, "content.html")
            File.write(file_path, content[:content])
            results[:html] = {
              path: file_path.to_s,
              preview: content[:content][0..500],
              size: content[:content].length
            }
          end
        when 'screenshot'
          # In production, this would use a service like Puppeteer or Playwright
          results[:screenshot] = {
            path: nil,
            message: "Screenshot functionality requires headless browser integration"
          }
        end
      end
      
      {
        success: true,
        url: url,
        formats: formats,
        results: results,
        temp_directory: temp_dir
      }
    rescue => e
      Rails.logger.error "[ContentFetcher] Website fetch failed: #{e.message}"
      { success: false, error: e.message }
    end

    # Search for real images about specific topics
    def search_images(query, num_results: 5)
      # This would integrate with image search APIs like Unsplash, Pexels, or Google Images
      Rails.logger.info "[ContentFetcher] Searching for images: #{query}"
      
      {
        success: true,
        query: query,
        images: [
          {
            url: "https://source.unsplash.com/800x600/?#{URI.encode_www_form_component(query)}",
            title: "#{query} image 1",
            source: "Unsplash",
            width: 800,
            height: 600
          }
        ]
      }
    end

    private

    def download_file(url)
      uri = URI.parse(url)
      
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
        request = Net::HTTP::Get.new(uri)
        request['User-Agent'] = 'OverSkill/1.0 ContentFetcher'
        http.request(request)
      end
      
      if response.code == '200'
        content_length = response['Content-Length'].to_i
        
        if content_length > MAX_DOWNLOAD_SIZE
          return { success: false, error: "File too large: #{content_length} bytes (max: #{MAX_DOWNLOAD_SIZE})" }
        end
        
        {
          success: true,
          content: response.body,
          size: response.body.length,
          content_type: response['Content-Type']
        }
      else
        { success: false, error: "HTTP #{response.code}: #{response.message}" }
      end
    rescue => e
      { success: false, error: "Download failed: #{e.message}" }
    end

    def fetch_as_html(url)
      uri = URI.parse(url)
      
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
        request = Net::HTTP::Get.new(uri)
        request['User-Agent'] = 'OverSkill/1.0 ContentFetcher'
        http.request(request)
      end
      
      if response.code == '200'
        { success: true, content: response.body }
      else
        { success: false, error: "HTTP #{response.code}" }
      end
    rescue => e
      { success: false, error: e.message }
    end

    def fetch_as_markdown(url)
      # In production, this would use a service to convert HTML to Markdown
      # For now, we'll fetch HTML and do basic conversion
      html_result = fetch_as_html(url)
      
      if html_result[:success]
        # Basic HTML to Markdown conversion (in production, use a proper converter)
        markdown = convert_html_to_markdown(html_result[:content])
        { success: true, content: markdown }
      else
        html_result
      end
    end

    def convert_html_to_markdown(html)
      # Very basic conversion - in production use a proper HTML to Markdown converter
      markdown = html
        .gsub(/<script[^>]*>.*?<\/script>/mi, '') # Remove scripts
        .gsub(/<style[^>]*>.*?<\/style>/mi, '')   # Remove styles
        .gsub(/<h1[^>]*>(.*?)<\/h1>/i) { "# #{$1}\n\n" }
        .gsub(/<h2[^>]*>(.*?)<\/h2>/i) { "## #{$1}\n\n" }
        .gsub(/<h3[^>]*>(.*?)<\/h3>/i) { "### #{$1}\n\n" }
        .gsub(/<p[^>]*>(.*?)<\/p>/i) { "#{$1}\n\n" }
        .gsub(/<a[^>]*href=["']([^"']+)["'][^>]*>(.*?)<\/a>/i) { "[#{$2}](#{$1})" }
        .gsub(/<img[^>]*src=["']([^"']+)["'][^>]*alt=["']([^"']*)"[^>]*>/i) { "![#{$2}](#{$1})" }
        .gsub(/<[^>]+>/, '') # Remove remaining HTML tags
        .gsub(/\n{3,}/, "\n\n") # Clean up excessive newlines
        .strip
      
      markdown
    end

    def ensure_assets_path(path)
      # Ensure images go to src/assets folder
      unless path.start_with?('src/assets/')
        filename = File.basename(path)
        path = "src/assets/#{filename}"
      end
      path
    end

    def detect_file_type(path)
      extension = File.extname(path).downcase
      
      case extension
      when '.html' then 'html'
      when '.css' then 'css'
      when '.js', '.jsx' then 'js'
      when '.ts', '.tsx' then 'typescript'
      when '.json' then 'json'
      when '.md' then 'markdown'
      when '.svg' then 'svg'
      when *ALLOWED_IMAGE_TYPES then 'image'
      else 'text'
      end
    end

    def generate_mock_results(query, num_results, category)
      # Mock search results for demonstration
      # In production, this would call a real search API
      
      results = []
      num_results.times do |i|
        results << {
          title: "#{query} - Result #{i + 1}",
          url: "https://example.com/#{query.downcase.gsub(' ', '-')}-#{i + 1}",
          snippet: "This is a relevant result about #{query}. It contains useful information that can help with development.",
          category: category || 'general'
        }
      end
      
      results
    end
  end
end