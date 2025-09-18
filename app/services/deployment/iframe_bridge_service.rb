module Deployment
  # Bridge service for iframe communication enabling AI debugging capabilities
  # Similar to Lovable's console access but for deployed Cloudflare Worker apps
  class IframeBridgeService
    CONSOLE_LOG_TTL = 300 # 5 minutes
    MAX_LOG_ENTRIES = 1000
    MAX_NETWORK_ENTRIES = 500

    def initialize(app)
      @app = app
      @redis = Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1"))
    end

    # Setup console logging bridge in deployed app
    def setup_console_bridge
      bridge_code = generate_bridge_javascript

      # This would be injected into the deployed app's HTML
      # The bridge captures console logs and network requests
      {
        success: true,
        bridge_code: bridge_code,
        bridge_endpoint: bridge_endpoint_url
      }
    end

    # Read console logs for AI debugging (similar to Lovable's lov-read-console-logs)
    def read_console_logs(search_term = nil, limit = 100)
      logs_key = console_logs_cache_key

      begin
        # Get logs from Redis cache
        raw_logs = @redis.lrange(logs_key, 0, limit - 1)
        logs = raw_logs.map { |log| JSON.parse(log) }

        # Filter by search term if provided
        if search_term.present?
          logs = logs.select do |log|
            log["message"]&.include?(search_term) ||
              log["level"]&.include?(search_term) ||
              log["stack"]&.include?(search_term)
          end
        end

        {
          success: true,
          logs: logs,
          total_count: logs.length,
          search_term: search_term
        }
      rescue => e
        Rails.logger.error "[IframeBridge] Error reading console logs: #{e.message}"
        {success: false, error: e.message}
      end
    end

    # Read network requests for AI debugging (similar to Lovable's lov-read-network-requests)
    def read_network_requests(search_term = nil, limit = 50)
      requests_key = network_requests_cache_key

      begin
        # Get network requests from Redis cache
        raw_requests = @redis.lrange(requests_key, 0, limit - 1)
        requests = raw_requests.map { |request| JSON.parse(request) }

        # Filter by search term if provided
        if search_term.present?
          requests = requests.select do |request|
            request["url"]&.include?(search_term) ||
              request["method"]&.include?(search_term) ||
              request["status"]&.to_s&.include?(search_term) ||
              request["error"]&.include?(search_term)
          end
        end

        {
          success: true,
          requests: requests,
          total_count: requests.length,
          search_term: search_term
        }
      rescue => e
        Rails.logger.error "[IframeBridge] Error reading network requests: #{e.message}"
        {success: false, error: e.message}
      end
    end

    # Store console log from iframe (called by bridge endpoint)
    def store_console_log(log_data)
      logs_key = console_logs_cache_key

      # Add timestamp and app context
      enriched_log = {
        app_id: @app.id,
        timestamp: Time.current.iso8601,
        level: log_data[:level] || "log",
        message: log_data[:message],
        stack: log_data[:stack],
        url: log_data[:url],
        line_number: log_data[:line_number],
        column_number: log_data[:column_number]
      }

      # Store in Redis with automatic expiration
      @redis.multi do |pipeline|
        pipeline.lpush(logs_key, enriched_log.to_json)
        pipeline.ltrim(logs_key, 0, MAX_LOG_ENTRIES - 1) # Keep only recent logs
        pipeline.expire(logs_key, CONSOLE_LOG_TTL)
      end

      Rails.logger.info "[IframeBridge] Stored console log for app #{@app.id}: #{log_data[:level]} - #{log_data[:message]}"
    end

    # Store network request from iframe (called by bridge endpoint)
    def store_network_request(request_data)
      requests_key = network_requests_cache_key

      # Add timestamp and app context
      enriched_request = {
        app_id: @app.id,
        timestamp: Time.current.iso8601,
        method: request_data[:method],
        url: request_data[:url],
        status: request_data[:status],
        response_time: request_data[:response_time],
        error: request_data[:error],
        request_headers: request_data[:request_headers]&.slice("content-type", "authorization")&.transform_values { |v| v.include?("Bearer") ? "[REDACTED]" : v },
        response_headers: request_data[:response_headers]&.slice("content-type", "cache-control")
      }

      # Store in Redis with automatic expiration
      @redis.multi do |pipeline|
        pipeline.lpush(requests_key, enriched_request.to_json)
        pipeline.ltrim(requests_key, 0, MAX_NETWORK_ENTRIES - 1) # Keep only recent requests
        pipeline.expire(requests_key, CONSOLE_LOG_TTL)
      end

      Rails.logger.info "[IframeBridge] Stored network request for app #{@app.id}: #{request_data[:method]} #{request_data[:url]} - #{request_data[:status]}"
    end

    # Clear logs and network data (for privacy/cleanup)
    def clear_debugging_data
      @redis.del(console_logs_cache_key)
      @redis.del(network_requests_cache_key)

      Rails.logger.info "[IframeBridge] Cleared debugging data for app #{@app.id}"
    end

    private

    def console_logs_cache_key
      "iframe_bridge:console_logs:#{@app.id}"
    end

    def network_requests_cache_key
      "iframe_bridge:network_requests:#{@app.id}"
    end

    def bridge_endpoint_url
      "#{ENV.fetch("APP_BASE_URL", "https://overskill.app")}/api/v1/iframe_bridge/#{@app.id}/log"
    end

    # Generate JavaScript bridge code to inject into deployed apps
    def generate_bridge_javascript
      <<~JAVASCRIPT
        // OverSkill AI Debugging Bridge
        (function() {
          const BRIDGE_ENDPOINT = '#{bridge_endpoint_url}';
          const APP_ID = '#{@app.id}';
          
          // Console logging bridge
          const originalConsole = {
            log: console.log,
            warn: console.warn,
            error: console.error,
            info: console.info
          };
          
          function captureConsoleLog(level, args) {
            // Call original console method
            originalConsole[level].apply(console, args);
            
            // Send to OverSkill bridge
            const logData = {
              level: level,
              message: args.map(arg => {
                if (typeof arg === 'object') {
                  try {
                    return JSON.stringify(arg);
                  } catch(e) {
                    return String(arg);
                  }
                }
                return String(arg);
              }).join(' '),
              url: window.location.href,
              timestamp: new Date().toISOString()
            };
            
            // Send log to bridge (non-blocking)
            fetch(BRIDGE_ENDPOINT, {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ type: 'console', data: logData })
            }).catch(() => {}); // Silent fail
          }
          
          // Override console methods
          console.log = (...args) => captureConsoleLog('log', args);
          console.warn = (...args) => captureConsoleLog('warn', args);
          console.error = (...args) => captureConsoleLog('error', args);
          console.info = (...args) => captureConsoleLog('info', args);
          
          // Network request monitoring
          const originalFetch = window.fetch;
          window.fetch = function(...args) {
            const startTime = performance.now();
            const url = args[0];
            const options = args[1] || {};
            
            return originalFetch.apply(this, args)
              .then(response => {
                const endTime = performance.now();
                
                // Capture network request data
                const requestData = {
                  method: options.method || 'GET',
                  url: url,
                  status: response.status,
                  response_time: Math.round(endTime - startTime),
                  request_headers: options.headers || {},
                  response_headers: Object.fromEntries(response.headers.entries())
                };
                
                // Send to bridge (non-blocking)
                fetch(BRIDGE_ENDPOINT, {
                  method: 'POST',
                  headers: { 'Content-Type': 'application/json' },
                  body: JSON.stringify({ type: 'network', data: requestData })
                }).catch(() => {}); // Silent fail
                
                return response;
              })
              .catch(error => {
                const endTime = performance.now();
                
                // Capture network error
                const requestData = {
                  method: options.method || 'GET',
                  url: url,
                  status: 0,
                  response_time: Math.round(endTime - startTime),
                  error: error.message
                };
                
                // Send to bridge (non-blocking)
                fetch(BRIDGE_ENDPOINT, {
                  method: 'POST',
                  headers: { 'Content-Type': 'application/json' },
                  body: JSON.stringify({ type: 'network', data: requestData })
                }).catch(() => {}); // Silent fail
                
                throw error;
              });
          };
          
          // Global error handler
          window.addEventListener('error', function(event) {
            const errorData = {
              level: 'error',
              message: event.message,
              url: event.filename,
              line_number: event.lineno,
              column_number: event.colno,
              stack: event.error ? event.error.stack : null
            };
            
            fetch(BRIDGE_ENDPOINT, {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ type: 'console', data: errorData })
            }).catch(() => {});
          });
          
          console.log('OverSkill AI Debugging Bridge initialized for app #{@app.id}');
        })();
      JAVASCRIPT
    end
  end
end
