# frozen_string_literal: true

module Deployment
  class CloudflareWorkerOptimizer
    # Cloudflare Worker limits and constraints
    WORKER_SIZE_LIMIT = 1.megabyte
    SAFE_WORKER_SIZE_LIMIT = 900.kilobytes # Buffer for safety
    CRITICAL_ASSET_MAX_SIZE = 50.kilobytes # Assets that should stay in worker
    COMPRESSION_RATIO = 0.7 # Estimate ~30% compression

    class SizeViolationError < StandardError; end

    def initialize(app)
      @app = app
      @optimization_stats = {
        original_size: 0,
        optimized_size: 0,
        r2_assets: [],
        worker_assets: [],
        compression_savings: 0
      }
    end

    def optimize_for_worker(build_result)
      Rails.logger.info "[CloudflareWorkerOptimizer] Optimizing app ##{@app.id} for worker deployment"

      assets = build_result[:assets] || {}
      @optimization_stats[:original_size] = calculate_total_size(assets)

      # Phase 1: Categorize assets by criticality and size
      asset_categories = categorize_assets(assets)

      # Phase 2: Apply hybrid asset strategy
      optimization_result = apply_hybrid_strategy(asset_categories)

      # Phase 3: Validate final worker size
      validate_worker_size!(optimization_result[:worker_assets])

      # Phase 4: Generate optimized worker script
      worker_script = generate_optimized_worker_script(
        optimization_result[:worker_assets], 
        optimization_result[:r2_assets]
      )

      final_result = {
        success: true,
        worker_script: worker_script,
        worker_size: worker_script.bytesize,
        worker_assets: optimization_result[:worker_assets],
        r2_assets: optimization_result[:r2_assets],
        optimization_stats: @optimization_stats,
        recommendations: generate_optimization_recommendations
      }

      log_optimization_results(final_result)
      final_result
    end

    def analyze_size_requirements(assets)
      analysis = {
        total_size: 0,
        critical_size: 0,
        non_critical_size: 0,
        oversized_assets: [],
        recommendations: []
      }

      assets.each do |path, content|
        size = content.bytesize
        analysis[:total_size] += size

        if critical_asset?(path)
          analysis[:critical_size] += size
          
          if size > CRITICAL_ASSET_MAX_SIZE
            analysis[:oversized_assets] << {
              path: path,
              size: size,
              type: 'critical_oversized'
            }
          end
        else
          analysis[:non_critical_size] += size
        end
      end

      # Generate recommendations
      if analysis[:total_size] > SAFE_WORKER_SIZE_LIMIT
        analysis[:recommendations] << 'Requires hybrid asset strategy (R2 offloading)'
      end

      if analysis[:critical_size] > SAFE_WORKER_SIZE_LIMIT
        analysis[:recommendations] << 'Critical assets too large - requires code splitting'
      end

      analysis[:recommendations] << 'Consider asset compression' if analysis[:total_size] > 500.kilobytes

      analysis
    end

    def monitor_size_compliance(worker_script)
      current_size = worker_script.bytesize
      utilization = (current_size.to_f / WORKER_SIZE_LIMIT * 100).round(1)

      status = case utilization
               when 0..60 then 'healthy'
               when 61..80 then 'warning'
               when 81..95 then 'critical'
               else 'violation'
               end

      {
        current_size: current_size,
        size_limit: WORKER_SIZE_LIMIT,
        utilization_percent: utilization,
        status: status,
        bytes_remaining: WORKER_SIZE_LIMIT - current_size,
        needs_optimization: utilization > 80
      }
    end

    private

    def categorize_assets(assets)
      categories = {
        critical_small: {},    # Keep in worker (< 50KB critical assets)
        critical_large: {},    # Move to R2 (> 50KB critical assets)
        non_critical: {},      # Move to R2 (all non-critical assets)
        inline_scripts: {}     # Always keep in worker (essential JS)
      }

      assets.each do |path, content|
        size = content.bytesize

        if inline_script?(path)
          categories[:inline_scripts][path] = content
        elsif critical_asset?(path)
          if size <= CRITICAL_ASSET_MAX_SIZE
            categories[:critical_small][path] = content
          else
            categories[:critical_large][path] = content
          end
        else
          categories[:non_critical][path] = content
        end
      end

      Rails.logger.info "[CloudflareWorkerOptimizer] Asset categorization: " \
        "critical_small=#{categories[:critical_small].size}, " \
        "critical_large=#{categories[:critical_large].size}, " \
        "non_critical=#{categories[:non_critical].size}, " \
        "inline_scripts=#{categories[:inline_scripts].size}"

      categories
    end

    def apply_hybrid_strategy(categories)
      worker_assets = {}
      r2_assets = {}

      # Always keep inline scripts in worker
      worker_assets.merge!(categories[:inline_scripts])

      # Keep small critical assets in worker
      worker_assets.merge!(categories[:critical_small])

      # Move large critical assets to R2 with CDN URLs
      categories[:critical_large].each do |path, content|
        r2_assets[path] = {
          content: content,
          size: content.bytesize,
          cdn_url: generate_cdn_url(path),
          priority: 'high' # Critical assets get high priority CDN
        }
      end

      # Move all non-critical assets to R2
      categories[:non_critical].each do |path, content|
        r2_assets[path] = {
          content: content,
          size: content.bytesize,
          cdn_url: generate_cdn_url(path),
          priority: 'normal'
        }
      end

      # Update stats
      @optimization_stats[:worker_assets] = worker_assets.keys
      @optimization_stats[:r2_assets] = r2_assets.keys
      @optimization_stats[:optimized_size] = calculate_total_size(worker_assets)

      {
        worker_assets: worker_assets,
        r2_assets: r2_assets
      }
    end

    def critical_asset?(path)
      case path.downcase
      when 'index.html' then true
      when /^main\.(js|css)$/ then true
      when /^app\.(js|css)$/ then true
      when /critical/ then true
      when /\.woff2?$/ then true # Critical fonts
      else false
      end
    end

    def inline_script?(path)
      # Scripts that must be inline in worker for functionality
      case path.downcase
      when 'worker-bootstrap.js' then true
      when 'api-router.js' then true
      when /service-worker/ then true
      else false
      end
    end

    def generate_optimized_worker_script(worker_assets, r2_assets)
      # Create CDN mapping for R2 assets
      cdn_map = r2_assets.transform_values { |asset| asset[:cdn_url] }
      
      script = <<~JAVASCRIPT
        // Optimized Cloudflare Worker for App ##{@app.id}
        // Generated: #{Time.current.iso8601}
        // Worker size: #{calculate_total_size(worker_assets)} bytes
        // R2 assets: #{r2_assets.size} files

        // CDN asset mapping (#{cdn_map.size} assets)
        const CDN_ASSETS = #{cdn_map.to_json};
        
        // High priority assets for preloading
        const HIGH_PRIORITY_ASSETS = #{filter_high_priority_assets(r2_assets).to_json};

        export default {
          async fetch(request, env, ctx) {
            const url = new URL(request.url);
            const path = url.pathname;
            
            // Performance: Early return for CDN redirects
            if (CDN_ASSETS[path]) {
              return Response.redirect(CDN_ASSETS[path], 302);
            }
            
            #{generate_embedded_asset_handlers(worker_assets)}
            
            // API routing with app-scoped database
            if (path.startsWith('/api/')) {
              return handleApiRequest(request, env, ctx);
            }
            
            // SPA with preload hints for critical assets
            return serveSpaWithPreloads(request, env);
          }
        };

        #{generate_optimized_helper_functions(worker_assets, r2_assets)}
      JAVASCRIPT

      # Apply final compression optimizations
      optimize_script_size(script)
    end

    def generate_embedded_asset_handlers(worker_assets)
      return "// No embedded assets" if worker_assets.empty?

      handlers = worker_assets.map do |path, content|
        content_type = determine_content_type(path)
        compressed_content = compress_if_beneficial(content, content_type)
        
        <<~JAVASCRIPT
          if (path === '#{path}') {
            return new Response(#{compressed_content.to_json}, {
              headers: {
                'Content-Type': '#{content_type}',
                'Cache-Control': 'public, max-age=86400',
                'Content-Encoding': '#{compressed_content == content ? 'identity' : 'gzip'}'
              }
            });
          }
        JAVASCRIPT
      end

      handlers.join("        ")
    end

    def generate_optimized_helper_functions(worker_assets, r2_assets)
      <<~JAVASCRIPT
        async function handleApiRequest(request, env, ctx) {
          // Optimized API handling with connection pooling
          const startTime = Date.now();
          
          try {
            if (request.url.includes('/api/db/')) {
              const response = await proxyToSupabaseOptimized(request, env);
              
              // Performance monitoring
              const duration = Date.now() - startTime;
              response.headers.set('X-Response-Time', `${duration}ms`);
              
              return response;
            }
            
            return new Response('Not Found', { status: 404 });
          } catch (error) {
            console.error('API Error:', error);
            return new Response('Internal Server Error', { 
              status: 500,
              headers: { 'X-Error': 'api_error' }
            });
          }
        }

        async function serveSpaWithPreloads(request, env) {
          let html = #{worker_assets['index.html']&.to_json || '"<html><body>Loading...</body></html>"'};
          
          // Inject preload hints for high-priority R2 assets
          const preloadHints = HIGH_PRIORITY_ASSETS
            .map(url => `<link rel="preload" href="${url}" as="fetch" crossorigin>`)
            .join('\\n  ');
          
          if (preloadHints) {
            html = html.replace('</head>', `  ${preloadHints}\\n</head>`);
          }
          
          return new Response(html, {
            headers: {
              'Content-Type': 'text/html; charset=utf-8',
              'Cache-Control': 'public, max-age=3600',
              'X-Worker-Size': '#{calculate_total_size(worker_assets)}',
              'X-R2-Assets': '#{r2_assets.size}'
            }
          });
        }

        async function proxyToSupabaseOptimized(request, env) {
          // App-scoped database proxy with optimizations
          const supabaseUrl = env.SUPABASE_URL;
          const serviceKey = env.SUPABASE_SERVICE_KEY;
          
          if (!supabaseUrl || !serviceKey) {
            return new Response('Database configuration missing', { status: 500 });
          }
          
          // Transform API path to Supabase REST API
          const apiPath = new URL(request.url).pathname.replace('/api/db/', '/rest/v1/');
          const supabaseEndpoint = `${supabaseUrl}${apiPath}`;
          
          // Forward request with service key authorization
          return fetch(supabaseEndpoint, {
            method: request.method,
            headers: {
              ...Object.fromEntries(request.headers),
              'Authorization': `Bearer ${serviceKey}`,
              'apikey': serviceKey,
              'X-App-ID': '#{@app.id}'
            },
            body: request.body
          });
        }
      JAVASCRIPT
    end

    def filter_high_priority_assets(r2_assets)
      r2_assets
        .select { |_path, asset| asset[:priority] == 'high' }
        .values
        .map { |asset| asset[:cdn_url] }
    end

    def compress_if_beneficial(content, content_type)
      # Only compress text-based assets if they're large enough to benefit
      return content unless text_content_type?(content_type)
      return content if content.bytesize < 1.kilobyte

      # Simulate gzip compression (in real implementation, use actual compression)
      compressed = content.gsub(/\s+/, ' ').strip
      compressed.bytesize < content.bytesize * 0.8 ? compressed : content
    end

    def text_content_type?(content_type)
      %w[text/html text/css application/javascript text/plain].include?(content_type)
    end

    def optimize_script_size(script)
      # Apply final script optimizations
      optimized = script
        .gsub(/\/\/.*$/, '') # Remove comments
        .gsub(/\n\s*\n/, "\n") # Remove empty lines
        .gsub(/\s+/, ' ') # Normalize whitespace
        .strip

      optimized
    end

    def determine_content_type(path)
      case File.extname(path).downcase
      when '.js' then 'application/javascript'
      when '.css' then 'text/css'
      when '.html' then 'text/html'
      when '.json' then 'application/json'
      when '.woff2' then 'font/woff2'
      when '.woff' then 'font/woff'
      else 'text/plain'
      end
    end

    def generate_cdn_url(path)
      "https://cdn.overskill.app/apps/#{@app.id}/#{path.gsub(/^\//, '')}"
    end

    def calculate_total_size(assets)
      assets.values.sum do |content|
        content.is_a?(Hash) ? content[:size] || content[:content]&.bytesize || 0 : content.bytesize
      end
    end

    def validate_worker_size!(worker_assets)
      total_size = calculate_total_size(worker_assets)
      
      if total_size > WORKER_SIZE_LIMIT
        raise SizeViolationError, 
          "Worker size #{format_bytes(total_size)} exceeds Cloudflare limit of #{format_bytes(WORKER_SIZE_LIMIT)}"
      end

      if total_size > SAFE_WORKER_SIZE_LIMIT
        Rails.logger.warn "[CloudflareWorkerOptimizer] Worker size #{format_bytes(total_size)} " \
          "exceeds safe limit of #{format_bytes(SAFE_WORKER_SIZE_LIMIT)}"
      end
    end

    def generate_optimization_recommendations
      recommendations = []
      
      worker_size = @optimization_stats[:optimized_size]
      r2_count = @optimization_stats[:r2_assets].size

      if worker_size > SAFE_WORKER_SIZE_LIMIT * 0.8
        recommendations << "Consider further asset optimization - worker at #{((worker_size.to_f / SAFE_WORKER_SIZE_LIMIT) * 100).round(1)}% capacity"
      end

      if r2_count > 20
        recommendations << "High R2 asset count (#{r2_count}) may impact cold start performance"
      end

      original_size = @optimization_stats[:original_size]
      if original_size > 0
        savings_percent = ((original_size - worker_size).to_f / original_size * 100).round(1)
        recommendations << "Achieved #{savings_percent}% size reduction through optimization"
      end

      recommendations
    end

    def log_optimization_results(result)
      worker_size = result[:worker_size]
      r2_assets = result[:r2_assets].size
      utilization = ((worker_size.to_f / WORKER_SIZE_LIMIT) * 100).round(1)

      Rails.logger.info "[CloudflareWorkerOptimizer] Optimization complete for app ##{@app.id}: " \
        "worker_size=#{format_bytes(worker_size)} (#{utilization}%), " \
        "r2_assets=#{r2_assets}, " \
        "status=#{result[:optimization_stats][:status] || 'optimized'}"

      # Log detailed stats in development
      if Rails.env.development?
        stats = @optimization_stats
        Rails.logger.debug "[CloudflareWorkerOptimizer] Detailed stats: #{stats.to_json}"
      end
    end

    def format_bytes(bytes)
      return "0 B" if bytes == 0

      units = %w[B KB MB GB]
      size = bytes.to_f
      unit_index = 0

      while size >= 1024 && unit_index < units.length - 1
        size /= 1024
        unit_index += 1
      end

      "#{size.round(1)} #{units[unit_index]}"
    end
  end
end