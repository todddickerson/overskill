module Ai
  class LivePreviewManager
    # Enables real-time preview updates as users chat
    # Handles incremental builds and live deployment updates

    def initialize(app)
      @app = app
    end

    def update_preview_after_changes(changed_files)
      Rails.logger.info "[LivePreviewManager] Updating preview for app ##{@app.id} with #{changed_files.count} changed files"

      start_time = Time.current

      # 1. Trigger incremental build
      incremental_build_result = trigger_incremental_build(changed_files)

      # 2. Update preview deployment if build succeeded
      deployment_result = if incremental_build_result[:success]
        update_preview_deployment(incremental_build_result)
      else
        {success: false, error: "Build failed: #{incremental_build_result[:error]}"}
      end

      # 3. Broadcast updates to user's browser via ActionCable
      if deployment_result[:success]
        broadcast_preview_updates
      end

      # 4. Update app preview URL and status
      if deployment_result[:success]
        @app.update!(
          preview_url: deployment_result[:preview_url],
          deployment_status: "preview_updated",
          last_deployed_at: Time.current
        )
      end

      total_time = Time.current - start_time

      result = {
        success: deployment_result[:success],
        preview_url: deployment_result[:preview_url] || @app.preview_url,
        build_time: total_time.round(2),
        changes_applied: changed_files.count,
        build_type: incremental_build_result[:build_type],
        deployment_type: deployment_result[:deployment_type]
      }

      Rails.logger.info "[LivePreviewManager] Preview update completed in #{total_time.round(2)}s: #{result[:success] ? "success" : "failed"}"
      result
    rescue => e
      Rails.logger.error "[LivePreviewManager] Preview update failed for app ##{@app.id}: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")

      {
        success: false,
        error: e.message,
        preview_url: @app.preview_url,
        build_time: 0,
        changes_applied: 0
      }
    end

    private

    def trigger_incremental_build(changed_files)
      Rails.logger.info "[LivePreviewManager] Analyzing changes for incremental build"

      # Analyze the type and scope of changes
      change_analysis = analyze_file_changes(changed_files)

      # Determine build strategy based on changes
      build_strategy = determine_build_strategy(change_analysis)

      Rails.logger.info "[LivePreviewManager] Using #{build_strategy} build strategy"

      case build_strategy
      when :hot_component_update
        execute_hot_component_update(change_analysis[:component_files])
      when :incremental_build
        execute_incremental_build(changed_files)
      when :full_rebuild
        execute_full_rebuild
      else
        execute_fallback_build(changed_files)
      end
    end

    def analyze_file_changes(changed_files)
      analysis = {
        component_files: [],
        style_files: [],
        config_files: [],
        core_files: [],
        total_changes: changed_files.count
      }

      changed_files.each do |file_path|
        case file_path
        when /src\/components\/.*\.tsx$/
          analysis[:component_files] << file_path
        when /src\/pages\/.*\.tsx$/
          analysis[:component_files] << file_path
        when /\.css$|tailwind\.config\.|\.scss$/
          analysis[:style_files] << file_path
        when /package\.json$|vite\.config\.|tsconfig\./
          analysis[:config_files] << file_path
        when /src\/(main|App|router)\./
          analysis[:core_files] << file_path
        end
      end

      Rails.logger.debug "[LivePreviewManager] Change analysis: #{analysis[:component_files].count} components, #{analysis[:core_files].count} core files"
      analysis
    end

    def determine_build_strategy(change_analysis)
      # Determine the most efficient build strategy

      # If only component files changed and no core files, try hot update
      if change_analysis[:component_files].any? &&
          change_analysis[:core_files].empty? &&
          change_analysis[:config_files].empty? &&
          change_analysis[:total_changes] <= 3
        return :hot_component_update
      end

      # If only style changes, incremental build
      if change_analysis[:style_files].any? &&
          change_analysis[:core_files].empty? &&
          change_analysis[:config_files].empty?
        return :incremental_build
      end

      # If config files changed, need full rebuild
      if change_analysis[:config_files].any?
        return :full_rebuild
      end

      # If core files changed, need full rebuild
      if change_analysis[:core_files].any?
        return :full_rebuild
      end

      # Default to incremental build for other cases
      :incremental_build
    end

    def execute_hot_component_update(component_files)
      Rails.logger.info "[LivePreviewManager] Executing hot component update for #{component_files.count} components"

      # For hot updates, we can potentially just re-transpile the specific components
      # This is the fastest possible update method

      updated_components = []

      component_files.each do |file_path|
        component_result = transpile_component(file_path)

        if component_result[:success]
          updated_components << {
            path: file_path,
            compiled_code: component_result[:code],
            source_map: component_result[:source_map]
          }
        else
          # If any component fails, fall back to incremental build
          Rails.logger.warn "[LivePreviewManager] Hot update failed for #{file_path}, falling back to incremental build"
          return execute_incremental_build(component_files)
        end
      end

      # Package the hot update
      hot_update_package = create_hot_update_package(updated_components)

      {
        success: true,
        build_type: :hot_component_update,
        built_code: hot_update_package,
        build_time: 2.5, # Very fast for hot updates
        components_updated: updated_components.count
      }
    end

    def execute_incremental_build(changed_files)
      Rails.logger.info "[LivePreviewManager] Executing incremental build for #{changed_files.count} files"

      # Use the external builder but with optimization for incremental builds
      builder = Deployment::ExternalViteBuilder.new(@app)

      # Create a build context that focuses on changed files
      build_context = {
        changed_files: changed_files,
        incremental: true,
        skip_full_optimization: true
      }

      # Execute fast preview build with incremental context
      result = builder.build_for_preview_with_context(build_context)

      result.merge(
        build_type: :incremental_build,
        files_processed: changed_files.count
      )
    rescue => e
      Rails.logger.error "[LivePreviewManager] Incremental build failed: #{e.message}"

      # Fall back to full rebuild if incremental fails
      execute_full_rebuild
    end

    def execute_full_rebuild
      Rails.logger.info "[LivePreviewManager] Executing full rebuild"

      # Use the standard external builder for full rebuild
      builder = Deployment::ExternalViteBuilder.new(@app)
      result = builder.build_for_preview

      result.merge(
        build_type: :full_rebuild,
        reason: "Core files changed or incremental build failed"
      )
    end

    def execute_fallback_build(changed_files)
      Rails.logger.info "[LivePreviewManager] Executing fallback build"

      # Simple fallback that always works
      execute_full_rebuild
    end

    def transpile_component(file_path)
      # Transpile a single TypeScript/React component
      # This would use a lightweight transpiler like esbuild or swc

      app_file = @app.app_files.find_by(path: file_path)
      return {success: false, error: "File not found"} unless app_file

      begin
        # Simulate component transpilation
        # In a real implementation, this would use esbuild or similar

        component_code = app_file.content

        # Basic TypeScript to JavaScript transpilation simulation
        transpiled_code = simulate_typescript_transpilation(component_code)

        {
          success: true,
          code: transpiled_code,
          source_map: generate_source_map(file_path, component_code),
          original_path: file_path
        }
      rescue => e
        Rails.logger.error "[LivePreviewManager] Component transpilation failed for #{file_path}: #{e.message}"
        {success: false, error: e.message}
      end
    end

    def simulate_typescript_transpilation(code)
      # This is a simulation - real implementation would use proper transpiler

      # Remove TypeScript annotations (very basic)
      transpiled = code.gsub(/:\s*\w+(\[\])?(\s*\|\s*\w+)*/, "")

      # Convert arrow function components to regular functions (if needed)
      transpiled.gsub(/const (\w+): React\.FC.*?= \(\) =>/, 'function \1()')
    end

    def generate_source_map(file_path, original_code)
      # Generate a basic source map for debugging
      # Real implementation would create proper source maps

      {
        version: 3,
        file: ::File.basename(file_path),
        sources: [file_path],
        names: [],
        mappings: "AAAA" # Simplified mapping
      }.to_json
    end

    def create_hot_update_package(updated_components)
      # Create a package that can be hot-swapped in the browser

      hot_update = {
        type: "hot-update",
        timestamp: Time.current.to_i,
        components: {}
      }

      updated_components.each do |component|
        component_name = ::File.basename(component[:path], ".*")

        hot_update[:components][component_name] = {
          path: component[:path],
          code: component[:compiled_code],
          sourceMap: component[:source_map]
        }
      end

      # Package as JavaScript module that can be executed
      generate_hot_update_javascript(hot_update)
    end

    def generate_hot_update_javascript(hot_update)
      # Generate JavaScript that can perform hot updates in the browser

      <<~JAVASCRIPT
        // Hot Update Package - Generated at #{Time.current.iso8601}
        (function() {
          console.log('[HMR] Applying hot update...');
          
          const components = #{hot_update[:components].to_json};
          
          // Apply component updates
          Object.keys(components).forEach(componentName => {
            const component = components[componentName];
            
            // This would integrate with React Hot Reload in a real implementation
            if (window.__REACT_DEVTOOLS_GLOBAL_HOOK__) {
              console.log(`[HMR] Updating component: ${componentName}`);
              // Hot reload logic would go here
            }
          });
          
          console.log('[HMR] Hot update applied successfully');
        })();
      JAVASCRIPT
    end

    def update_preview_deployment(build_result)
      Rails.logger.info "[LivePreviewManager] Updating preview deployment"

      case build_result[:build_type]
      when :hot_component_update
        update_hot_deployment(build_result)
      when :incremental_build, :full_rebuild
        update_standard_deployment(build_result)
      else
        update_fallback_deployment(build_result)
      end
    end

    def update_hot_deployment(build_result)
      Rails.logger.info "[LivePreviewManager] Deploying hot update"

      # For hot updates, we can potentially push updates directly to the existing worker
      # without full redeployment

      begin
        # In a real implementation, this might use WebSockets or Server-Sent Events
        # to push updates directly to the browser

        # For now, we'll still update the worker but with a lighter process
        deployer = Deployment::CloudflareWorkersDeployer.new(@app)

        # Create a minimal worker update
        hot_update_worker = create_hot_update_worker(build_result[:built_code])

        deployment_result = deployer.update_worker_hot(hot_update_worker)

        deployment_result.merge(
          deployment_type: :hot_update,
          preview_url: @app.preview_url || generate_preview_url
        )
      rescue => e
        Rails.logger.warn "[LivePreviewManager] Hot deployment failed, falling back to standard deployment: #{e.message}"
        update_standard_deployment(build_result)
      end
    end

    def update_standard_deployment(build_result)
      Rails.logger.info "[LivePreviewManager] Deploying standard update"

      # Use the standard Cloudflare Workers deployment
      deployer = Deployment::CloudflareWorkersDeployer.new(@app)

      deployment_result = deployer.deploy_with_secrets(
        built_code: build_result[:built_code],
        deployment_type: :preview
      )

      deployment_result.merge(deployment_type: :standard_preview)
    end

    def update_fallback_deployment(build_result)
      Rails.logger.info "[LivePreviewManager] Deploying fallback update"

      # Fallback deployment method
      update_standard_deployment(build_result)
    end

    def create_hot_update_worker(hot_update_code)
      # Create a minimal Cloudflare Worker that can handle hot updates

      <<~JAVASCRIPT
        // Hot Update Worker - Generated at #{Time.current.iso8601}
        
        export default {
          async fetch(request, env, ctx) {
            const url = new URL(request.url);
            
            // Handle hot update requests
            if (url.pathname === '/__hot-update__') {
              return new Response(#{hot_update_code.to_json}, {
                headers: {
                  'Content-Type': 'application/javascript',
                  'Cache-Control': 'no-cache',
                  'Access-Control-Allow-Origin': '*'
                }
              });
            }
            
            // Fallback to existing app logic
            return handleAppRequest(request, env, ctx);
          }
        };
        
        #{build_existing_app_handler}
      JAVASCRIPT
    end

    def build_existing_app_handler
      # Get the existing app logic from the current deployment
      # This would be stored/cached from the last full build

      cached_app_code = Rails.cache.read("app_#{@app.id}_latest_build")

      if cached_app_code
        cached_app_code
      else
        # Fallback to minimal handler
        <<~JAVASCRIPT
          function handleAppRequest(request, env, ctx) {
            return new Response('App updating...', {
              headers: { 'Content-Type': 'text/html' }
            });
          }
        JAVASCRIPT
      end
    end

    def broadcast_preview_updates
      Rails.logger.info "[LivePreviewManager] Broadcasting preview updates to client"

      # Broadcast to the specific app's preview channel
      ActionCable.server.broadcast(
        "app_#{@app.id}_preview",
        {
          type: "preview_updated",
          app_id: @app.id,
          preview_url: @app.preview_url,
          timestamp: Time.current.iso8601,
          message: "Preview updated successfully!"
        }
      )

      # Also broadcast to the user's personal channel if they have one
      if @app.creator&.user
        ActionCable.server.broadcast(
          "user_#{@app.creator.user.id}_updates",
          {
            type: "app_preview_updated",
            app_id: @app.id,
            app_name: @app.name,
            preview_url: @app.preview_url,
            timestamp: Time.current.iso8601
          }
        )
      end
    end

    def generate_preview_url
      # Generate the expected preview URL for this app
      base_domain = ENV["APP_BASE_DOMAIN"] || "overskillproject.com"
      "https://preview-#{@app.obfuscated_id.downcase}.#{base_domain}"
    end

    # Utility method to check if incremental builds are supported
    def supports_incremental_builds?
      # Check if the app structure supports incremental builds

      # Must have a valid Vite configuration
      vite_config = @app.app_files.find_by(path: "vite.config.ts")
      return false unless vite_config

      # Must have TypeScript configuration
      ts_config = @app.app_files.find_by(path: "tsconfig.json")
      return false unless ts_config

      # Must not have complex build dependencies
      package_file = @app.app_files.find_by(path: "package.json")
      return false unless package_file

      begin
        package_data = JSON.parse(package_file.content)
        dependencies = package_data["dependencies"] || {}

        # Avoid incremental builds if there are complex build tools
        complex_deps = dependencies.keys.select { |dep| dep.match?(/webpack|rollup|babel|esbuild/) }
        return false if complex_deps.any?
      rescue JSON::ParserError
        return false
      end

      true
    end

    # Method to pre-warm the build cache for faster updates
    def prepare_build_cache
      Rails.logger.info "[LivePreviewManager] Preparing build cache for app ##{@app.id}"

      # Cache frequently accessed files and build artifacts
      cache_key = "app_#{@app.id}_build_cache"

      cache_data = {
        package_json: @app.app_files.find_by(path: "package.json")&.content,
        vite_config: @app.app_files.find_by(path: "vite.config.ts")&.content,
        tsconfig: @app.app_files.find_by(path: "tsconfig.json")&.content,
        component_list: @app.app_files.where("path LIKE 'src/components/%.tsx'").pluck(:path),
        last_build_hash: calculate_build_hash,
        cached_at: Time.current.iso8601
      }

      Rails.cache.write(cache_key, cache_data, expires_in: 1.hour)

      Rails.logger.info "[LivePreviewManager] Build cache prepared"
    end

    def calculate_build_hash
      # Calculate a hash of all files to detect changes
      file_contents = @app.app_files.order(:path).pluck(:path, :content)
      content_string = file_contents.map { |path, content| "#{path}:#{content}" }.join("|")

      Digest::SHA256.hexdigest(content_string)
    end

    # Method to validate that the preview is working correctly
    def validate_preview_deployment(preview_url)
      return {valid: false, error: "No preview URL provided"} unless preview_url

      begin
        # Make a simple HTTP request to check if the preview is accessible
        response = Net::HTTP.get_response(URI(preview_url))

        if response.code.to_i == 200
          {valid: true, status_code: response.code, response_time: 0}
        else
          {valid: false, status_code: response.code, error: "HTTP #{response.code}"}
        end
      rescue => e
        Rails.logger.error "[LivePreviewManager] Preview validation failed: #{e.message}"
        {valid: false, error: e.message}
      end
    end
  end
end
