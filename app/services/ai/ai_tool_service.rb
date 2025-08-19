# frozen_string_literal: true

module Ai
  # Centralized service for all AI agent tool implementations
  # This service extracts tool functionality from AppBuilderV5 to maintain cleaner separation of concerns
  # Each tool method returns a standardized response hash with :success and :content/:error keys
  class AiToolService
    attr_reader :app, :logger
    
    def initialize(app, options = {})
      @app = app
      @logger = options[:logger] || Rails.logger
      @user = options[:user] || app&.team&.users&.first
      
      # Initialize dependent services
      @web_content_service = WebContentExtractionService.new
      @perplexity_service = PerplexityContentService.new
      @image_service = Ai::ImageGenerationService.new
      @search_service = Ai::SmartSearchService.new(app)
    end
    
    # ========================
    # File Management Tools
    # ========================
    
    def write_file(file_path, content)
      return { success: false, error: "File path cannot be blank" } if file_path.blank?
      return { success: false, error: "Content cannot be blank" } if content.blank?
      
      app_file = @app.app_files.find_or_initialize_by(path: file_path)
      app_file.content = content
      
      if app_file.save
        @logger.info "[AiToolService] File written: #{file_path} (#{content.length} chars)"
        { success: true, content: "File #{file_path} written successfully" }
      else
        { success: false, error: app_file.errors.full_messages.join(", ") }
      end
    rescue StandardError => e
      @logger.error "[AiToolService] Error writing file #{file_path}: #{e.message}"
      { success: false, error: e.message }
    end
    
    def read_file(file_path, lines = nil)
      app_file = @app.app_files.find_by(path: file_path)
      
      if app_file
        content = app_file.content || ""
        content = apply_line_filter(content, lines) if lines
        { success: true, content: content }
      else
        { success: false, error: "File not found: #{file_path}" }
      end
    rescue StandardError => e
      @logger.error "[AiToolService] Error reading file #{file_path}: #{e.message}"
      { success: false, error: e.message }
    end
    
    def delete_file(file_path)
      app_file = @app.app_files.find_by(path: file_path)
      
      if app_file
        app_file.destroy
        @logger.info "[AiToolService] File deleted: #{file_path}"
        { success: true, content: "File #{file_path} deleted successfully" }
      else
        { success: false, error: "File not found: #{file_path}" }
      end
    rescue StandardError => e
      @logger.error "[AiToolService] Error deleting file #{file_path}: #{e.message}"
      { success: false, error: e.message }
    end
    
    def rename_file(old_path, new_path)
      app_file = @app.app_files.find_by(path: old_path)
      
      if app_file
        app_file.path = new_path
        if app_file.save
          @logger.info "[AiToolService] File renamed: #{old_path} -> #{new_path}"
          { success: true, content: "File renamed from #{old_path} to #{new_path}" }
        else
          { success: false, error: app_file.errors.full_messages.join(", ") }
        end
      else
        { success: false, error: "File not found: #{old_path}" }
      end
    rescue StandardError => e
      @logger.error "[AiToolService] Error renaming file: #{e.message}"
      { success: false, error: e.message }
    end
    
    def replace_file_content(args)
      file_path = args['file_path'] || args[:file_path]
      search_pattern = args['search_pattern'] || args[:search_pattern]
      first_line = args['first_line'] || args[:first_line]
      last_line = args['last_line'] || args[:last_line]
      replacement = args['replacement'] || args[:replacement]
      
      # Find the file
      file = @app.app_files.find_by(path: file_path)
      return { success: false, error: "File not found: #{file_path}" } unless file
      
      # Use the class method instead of instance
      result = Ai::LineReplaceService.replace_lines(file, search_pattern, first_line, last_line, replacement)
      result
    rescue StandardError => e
      @logger.error "[AiToolService] Error in line replace: #{e.message}"
      { success: false, error: e.message }
    end
    
    # ========================
    # Search Tools
    # ========================
    
    def search_files(args)
      query = args['query'] || args[:query]
      include_pattern = args['include_pattern'] || args[:include_pattern] || '**/*'
      exclude_pattern = args['exclude_pattern'] || args[:exclude_pattern]
      case_sensitive = args['case_sensitive'] || args[:case_sensitive] || false
      
      results = @search_service.search_with_regex(
        query,
        include_pattern: include_pattern,
        exclude_pattern: exclude_pattern,
        case_sensitive: case_sensitive
      )
      
      formatted_results = results.map do |result|
        "#{result[:file]}: Line #{result[:line_number]}: #{result[:content]}"
      end.join("\n")
      
      { success: true, content: formatted_results }
    rescue StandardError => e
      @logger.error "[AiToolService] Error searching files: #{e.message}"
      { success: false, error: e.message }
    end
    
    # ========================
    # Web Research Tools
    # ========================
    
    def web_search(args)
      query = args['query'] || args[:query]
      num_results = args['numResults'] || args[:numResults] || 5
      category = args['category'] || args[:category]
      
      return { success: false, error: "Query is required" } if query.blank?
      
      # Use SerpAPI for web search
      api_key = ENV['SERPAPI_API_KEY'] || Rails.application.credentials.dig(:serpapi, :api_key)
      return { success: false, error: "SerpAPI key not configured" } unless api_key
      
      client = GoogleSearch.new(q: query, api_key: api_key, num: num_results)
      
      # Add category filter if specified
      if category.present?
        case category
        when "news"
          client = GoogleSearch.new(q: query, api_key: api_key, tbm: "nws", num: num_results)
        when "github"
          query = "site:github.com #{query}"
          client = GoogleSearch.new(q: query, api_key: api_key, num: num_results)
        when "pdf"
          query = "filetype:pdf #{query}"
          client = GoogleSearch.new(q: query, api_key: api_key, num: num_results)
        end
      end
      
      results = client.get_hash
      
      formatted_results = format_search_results(results)
      
      { success: true, content: formatted_results }
    rescue StandardError => e
      @logger.error "[AiToolService] Error in web search: #{e.message}"
      { success: false, error: e.message }
    end
    
    def fetch_webpage(url, use_cache = true)
      result = @web_content_service.extract_for_llm(url, use_cache: use_cache)
      
      if result[:error]
        { success: false, error: result[:error] }
      else
        content = format_webpage_content(result)
        { success: true, content: content }
      end
    rescue StandardError => e
      @logger.error "[AiToolService] Error fetching webpage: #{e.message}"
      { success: false, error: e.message }
    end
    
    def perplexity_research(args)
      query = args['query'] || args[:query]
      mode = args['mode'] || args[:mode] || 'quick'
      max_tokens = args['max_tokens'] || args[:max_tokens] || 2000
      use_cache = args.fetch('use_cache', true)
      
      return { success: false, error: "Query is required" } if query.blank?
      
      # Map mode to appropriate method and model
      result = case mode
      when 'fact_check'
        @perplexity_service.fact_check(query)
      when 'deep'
        @perplexity_service.deep_research(query)
      when 'research'
        @perplexity_service.extract_content_for_llm(
          query, 
          model: PerplexityContentService::MODELS[:sonar_pro],
          max_tokens: max_tokens,
          use_cache: use_cache
        )
      else # 'quick'
        @perplexity_service.extract_content_for_llm(
          query,
          model: PerplexityContentService::MODELS[:sonar],
          max_tokens: max_tokens,
          use_cache: use_cache
        )
      end
      
      if result[:error]
        { success: false, error: result[:error] }
      else
        content = format_perplexity_response(result, mode)
        { success: true, content: content }
      end
    rescue StandardError => e
      @logger.error "[AiToolService] Error in Perplexity research: #{e.message}"
      { success: false, error: e.message }
    end
    
    # ========================
    # Package Management Tools
    # ========================
    
    def add_dependency(package)
      package_json = @app.app_files.find_or_initialize_by(path: 'package.json')
      
      begin
        json = package_json.content.present? ? JSON.parse(package_json.content) : {}
        json['dependencies'] ||= {}
        
        # Parse package name and version
        if package.include?('@')
          name, version = package.rsplit('@', 2)
          version = version.presence || 'latest'
        else
          name = package
          version = 'latest'
        end
        
        json['dependencies'][name] = version
        package_json.content = JSON.pretty_generate(json)
        package_json.save!
        
        @logger.info "[AiToolService] Added dependency: #{name}@#{version}"
        { success: true, content: "Added dependency: #{name}@#{version}" }
      rescue StandardError => e
        @logger.error "[AiToolService] Error adding dependency: #{e.message}"
        { success: false, error: e.message }
      end
    end
    
    def remove_dependency(package)
      package_json = @app.app_files.find_by(path: 'package.json')
      return { success: false, error: "package.json not found" } unless package_json
      
      begin
        json = JSON.parse(package_json.content)
        
        if json['dependencies']&.key?(package)
          json['dependencies'].delete(package)
          package_json.content = JSON.pretty_generate(json)
          package_json.save!
          
          @logger.info "[AiToolService] Removed dependency: #{package}"
          { success: true, content: "Removed dependency: #{package}" }
        else
          { success: false, error: "Package #{package} not found in dependencies" }
        end
      rescue StandardError => e
        @logger.error "[AiToolService] Error removing dependency: #{e.message}"
        { success: false, error: e.message }
      end
    end
    
    # ========================
    # Image Generation Tools
    # ========================
    
    def generate_image(args)
      prompt = args['prompt'] || args[:prompt]
      target_path = args['target_path'] || args[:target_path]
      width = args['width'] || args[:width] || 1024
      height = args['height'] || args[:height] || 1024
      model = args['model'] || args[:model] || 'flux.schnell'
      
      return { success: false, error: "Prompt is required" } if prompt.blank?
      return { success: false, error: "Target path is required" } if target_path.blank?
      
      # Note: generate_and_save_image now returns R2 URLs
      result = @image_service.generate_and_save_image(
        prompt: prompt,
        target_path: target_path,
        width: width,
        height: height,
        model: model
      )
      
      if result[:success]
        @logger.info "[AiToolService] Image generated and uploaded to R2: #{target_path} -> #{result[:url]}"
        
        # Return enhanced response with R2 URL and usage instructions
        response = "Image generated successfully!\n\n"
        response += "Path: #{target_path}\n"
        response += "R2 URL: #{result[:url]}\n\n"
        response += "IMPORTANT: Use the R2 URL in your HTML/CSS, not the local path:\n"
        response += "Example HTML: <img src=\"#{result[:url]}\" alt=\"Generated image\" />\n"
        response += "Example CSS: background-image: url('#{result[:url]}');\n\n"
        response += "The image is hosted on Cloudflare R2 for optimal performance."
        
        { 
          success: true, 
          content: response,
          url: result[:url],
          path: target_path,
          storage_method: 'r2'
        }
      else
        { success: false, error: result[:error] }
      end
    rescue StandardError => e
      @logger.error "[AiToolService] Error generating image: #{e.message}"
      { success: false, error: e.message }
    end
    
    def edit_image(args)
      image_paths = args['image_paths'] || args[:image_paths]
      prompt = args['prompt'] || args[:prompt]
      target_path = args['target_path'] || args[:target_path]
      strength = args['strength'] || args[:strength] || 0.8
      
      return { success: false, error: "Image paths are required" } if image_paths.blank?
      return { success: false, error: "Prompt is required" } if prompt.blank?
      return { success: false, error: "Target path is required" } if target_path.blank?
      
      # Load source images
      source_images = image_paths.map do |path|
        file = @app.app_files.find_by(path: path)
        return { success: false, error: "Image not found: #{path}" } unless file
        file.content
      end
      
      result = @image_service.edit_image(
        images: source_images,
        prompt: prompt,
        target_path: target_path,
        strength: strength,
        app: @app
      )
      
      if result[:success]
        @logger.info "[AiToolService] Image edited: #{target_path}"
        { success: true, content: "Image edited and saved to #{target_path}" }
      else
        { success: false, error: result[:error] }
      end
    rescue StandardError => e
      @logger.error "[AiToolService] Error editing image: #{e.message}"
      { success: false, error: e.message }
    end
    
    # ========================
    # Utility Tools
    # ========================
    
    def download_to_repo(source_url, target_path)
      return { success: false, error: "Source URL is required" } if source_url.blank?
      return { success: false, error: "Target path is required" } if target_path.blank?
      
      require 'open-uri'
      require 'net/http'
      
      begin
        uri = URI(source_url)
        response = Net::HTTP.get_response(uri)
        
        if response.is_a?(Net::HTTPSuccess)
          content = response.body.force_encoding('UTF-8')
          
          app_file = @app.app_files.find_or_initialize_by(path: target_path)
          app_file.content = content
          app_file.save!
          
          @logger.info "[AiToolService] Downloaded #{source_url} to #{target_path}"
          { success: true, content: "File downloaded to #{target_path}" }
        else
          { success: false, error: "Failed to download: HTTP #{response.code}" }
        end
      rescue StandardError => e
        @logger.error "[AiToolService] Error downloading file: #{e.message}"
        { success: false, error: e.message }
      end
    end
    
    def fetch_website(url, formats = 'markdown')
      # This is a placeholder - would need proper implementation
      # For now, delegate to webpage fetching
      fetch_webpage(url, true)
    end
    
    def read_console_logs(search = nil)
      # Placeholder - would need integration with actual console logs
      { success: true, content: "Console logs not available in this context" }
    end
    
    def read_network_requests(search = nil)
      # Placeholder - would need integration with actual network monitoring
      { success: true, content: "Network requests not available in this context" }
    end
    
    def read_project_analytics(args)
      # Placeholder - would need integration with analytics service
      { success: true, content: "Analytics feature coming soon" }
    end
    
    private
    
    def apply_line_filter(content, lines)
      return content if lines.blank?
      
      line_array = content.lines
      ranges = parse_line_ranges(lines)
      
      selected_lines = []
      ranges.each do |range|
        start_line = [range[:start] - 1, 0].max
        end_line = [range[:end], line_array.length].min
        selected_lines.concat(line_array[start_line...end_line])
      end
      
      selected_lines.join
    end
    
    def parse_line_ranges(lines_str)
      ranges = []
      lines_str.split(',').each do |range_str|
        range_str = range_str.strip
        if range_str.include?('-')
          start_line, end_line = range_str.split('-').map(&:to_i)
          ranges << { start: start_line, end: end_line }
        else
          line_num = range_str.to_i
          ranges << { start: line_num, end: line_num }
        end
      end
      ranges
    end
    
    def format_search_results(results)
      return "No results found" if results['organic_results'].blank?
      
      formatted = []
      results['organic_results'].each_with_index do |result, i|
        formatted << "#{i + 1}. #{result['title']}"
        formatted << "   URL: #{result['link']}"
        formatted << "   #{result['snippet']}"
        formatted << ""
      end
      
      formatted.join("\n")
    end
    
    def format_webpage_content(result)
      lines = []
      lines << "=== Webpage Content Extracted ==="
      lines << "URL: #{result[:url]}"
      lines << "Title: #{result[:title]}" if result[:title].present?
      lines << "Word Count: #{result[:word_count]}"
      lines << "Character Count: #{result[:char_count]}"
      lines << "Extracted At: #{result[:extracted_at]}"
      lines << "⚠️ Content was truncated due to length" if result[:truncated]
      lines << ""
      lines << "=== Content ==="
      lines << result[:content]
      
      lines.join("\n")
    end
    
    def format_perplexity_response(result, mode)
      lines = []
      lines << "=== Perplexity Research Result ==="
      lines << "Query: #{result[:source] || result[:topic]}"
      lines << "Mode: #{mode}"
      lines << "Model: #{result[:model]}" if result[:model]
      lines << "Word Count: #{result[:word_count]}"
      lines << "Has Citations: #{result[:has_citations] ? 'Yes' : 'No'}"
      lines << "Estimated Cost: $#{result[:estimated_cost]}" if result[:estimated_cost]
      lines << "Timestamp: #{result[:extracted_at] || result[:researched_at]}"
      lines << ""
      lines << "=== Content ==="
      lines << (result[:content] || result[:research_report])
      
      lines.join("\n")
    end
  end
end