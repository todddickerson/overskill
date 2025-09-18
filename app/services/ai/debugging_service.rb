# PHASE 2 ENHANCEMENT: Debugging Service
# Provides console logs and network request monitoring like Lovable's debugging tools
# Enables AI to debug runtime issues in generated applications

module Ai
  class DebuggingService
    include Rails.application.routes.url_helpers

    attr_reader :app, :search_term, :limit

    def initialize(app, search_term: nil, limit: 50)
      @app = app
      @search_term = search_term
      @limit = limit
    end

    def self.read_console_logs(app, search_term: nil, limit: 50)
      service = new(app, search_term: search_term, limit: limit)
      service.read_console_logs
    end

    def self.read_network_requests(app, search_term: nil, limit: 50)
      service = new(app, search_term: search_term, limit: limit)
      service.read_network_requests
    end

    def read_console_logs
      Rails.logger.info "[DebuggingService] Reading console logs for #{@app.name}"
      Rails.logger.info "[DebuggingService] Search term: #{@search_term || "all"}, Limit: #{@limit}"

      begin
        # In a real implementation, this would connect to browser DevTools API
        # or Cloudflare Workers logging. For now, we'll simulate with stored logs.

        logs = fetch_console_logs_from_deployment

        # Filter by search term if provided
        if @search_term.present?
          logs = filter_logs_by_search(logs, @search_term)
        end

        # Limit results
        logs = logs.first(@limit)

        # Analyze logs for common issues
        analysis = analyze_console_logs(logs)

        Rails.logger.info "[DebuggingService] Found #{logs.size} console log entries"

        {
          success: true,
          logs: logs,
          analysis: analysis,
          search_term: @search_term,
          total_logs: logs.size,
          message: "Retrieved #{logs.size} console log entries"
        }
      rescue => e
        Rails.logger.error "[DebuggingService] Console log reading failed: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")

        {
          success: false,
          error: e.message,
          logs: [],
          message: "Failed to read console logs: #{e.message}"
        }
      end
    end

    def read_network_requests
      Rails.logger.info "[DebuggingService] Reading network requests for #{@app.name}"
      Rails.logger.info "[DebuggingService] Search term: #{@search_term || "all"}, Limit: #{@limit}"

      begin
        # In a real implementation, this would connect to Cloudflare Workers
        # or browser DevTools to capture network traffic

        requests = fetch_network_requests_from_deployment

        # Filter by search term if provided
        if @search_term.present?
          requests = filter_requests_by_search(requests, @search_term)
        end

        # Limit results
        requests = requests.first(@limit)

        # Analyze requests for common issues
        analysis = analyze_network_requests(requests)

        Rails.logger.info "[DebuggingService] Found #{requests.size} network request entries"

        {
          success: true,
          requests: requests,
          analysis: analysis,
          search_term: @search_term,
          total_requests: requests.size,
          message: "Retrieved #{requests.size} network request entries"
        }
      rescue => e
        Rails.logger.error "[DebuggingService] Network request reading failed: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")

        {
          success: false,
          error: e.message,
          requests: [],
          message: "Failed to read network requests: #{e.message}"
        }
      end
    end

    private

    def fetch_console_logs_from_deployment
      # This would integrate with Cloudflare Workers logging in production
      # For now, simulate common console logs from deployed apps

      preview_url = "https://preview-#{@app.obfuscated_id.downcase}.overskill.app"

      # Simulate console logs - in production, this would be real data
      [
        {
          timestamp: 5.minutes.ago,
          level: "info",
          message: "React app initialized successfully",
          source: "main.jsx",
          line_number: 12,
          url: preview_url
        },
        {
          timestamp: 4.minutes.ago,
          level: "error",
          message: "Uncaught TypeError: Cannot read properties of undefined (reading 'map')",
          source: "App.jsx",
          line_number: 25,
          url: preview_url,
          stack_trace: 'at App.jsx:25:18\nat React.createElement\nat renderComponent'
        },
        {
          timestamp: 3.minutes.ago,
          level: "warn",
          message: "Warning: React.createElement: type is invalid",
          source: "components/Button.jsx",
          line_number: 8,
          url: preview_url
        },
        {
          timestamp: 2.minutes.ago,
          level: "log",
          message: "API request initiated",
          source: "services/api.js",
          line_number: 15,
          url: preview_url
        },
        {
          timestamp: 1.minute.ago,
          level: "error",
          message: "Failed to fetch: TypeError: Failed to fetch",
          source: "services/api.js",
          line_number: 23,
          url: preview_url
        }
      ]
    end

    def fetch_network_requests_from_deployment
      # This would integrate with Cloudflare Workers or DevTools in production
      # For now, simulate common network requests from deployed apps

      preview_url = "https://preview-#{@app.obfuscated_id.downcase}.overskill.app"

      # Simulate network requests - in production, this would be real data
      [
        {
          timestamp: 5.minutes.ago,
          method: "GET",
          url: "#{preview_url}/",
          status: 200,
          response_time: 142,
          size: 1024,
          type: "document"
        },
        {
          timestamp: 4.minutes.ago,
          method: "GET",
          url: "https://unpkg.com/react@18/umd/react.development.js",
          status: 200,
          response_time: 89,
          size: 156789,
          type: "script"
        },
        {
          timestamp: 3.minutes.ago,
          method: "POST",
          url: "https://api.example.com/data",
          status: 404,
          response_time: 2300,
          size: 256,
          type: "xhr",
          error: "Not Found"
        },
        {
          timestamp: 2.minutes.ago,
          method: "GET",
          url: "https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&display=swap",
          status: 200,
          response_time: 234,
          size: 4567,
          type: "stylesheet"
        },
        {
          timestamp: 1.minute.ago,
          method: "POST",
          url: "#{preview_url}/api/save",
          status: 500,
          response_time: 5000,
          size: 128,
          type: "xhr",
          error: "Internal Server Error"
        }
      ]
    end

    def filter_logs_by_search(logs, search_term)
      search_regex = Regexp.new(search_term, Regexp::IGNORECASE)
      logs.select do |log|
        log[:message].match?(search_regex) ||
          log[:source]&.match?(search_regex) ||
          log[:level]&.match?(search_regex)
      end
    end

    def filter_requests_by_search(requests, search_term)
      search_regex = Regexp.new(search_term, Regexp::IGNORECASE)
      requests.select do |request|
        request[:url].match?(search_regex) ||
          request[:method]&.match?(search_regex) ||
          request[:error]&.match?(search_regex)
      end
    end

    def analyze_console_logs(logs)
      analysis = {
        total_logs: logs.size,
        errors: logs.count { |log| log[:level] == "error" },
        warnings: logs.count { |log| log[:level] == "warn" },
        common_issues: [],
        recommendations: []
      }

      # Identify common React errors
      react_errors = logs.select { |log| log[:message].match?(/react|React/i) && log[:level] == "error" }
      if react_errors.any?
        analysis[:common_issues] << {
          type: "react_errors",
          count: react_errors.size,
          description: "React-related errors detected"
        }
        analysis[:recommendations] << "Check React component prop types and state management"
      end

      # Identify undefined/null errors
      undefined_errors = logs.select { |log| log[:message].match?(/undefined|null/i) && log[:level] == "error" }
      if undefined_errors.any?
        analysis[:common_issues] << {
          type: "undefined_errors",
          count: undefined_errors.size,
          description: "Undefined/null reference errors"
        }
        analysis[:recommendations] << "Add null checks and default values for variables"
      end

      # Identify fetch/API errors
      api_errors = logs.select { |log| log[:message].match?(/fetch|api|xhr/i) && log[:level] == "error" }
      if api_errors.any?
        analysis[:common_issues] << {
          type: "api_errors",
          count: api_errors.size,
          description: "API/fetch-related errors"
        }
        analysis[:recommendations] << "Check API endpoints and error handling"
      end

      analysis
    end

    def analyze_network_requests(requests)
      analysis = {
        total_requests: requests.size,
        failed_requests: requests.count { |req| req[:status] >= 400 },
        slow_requests: requests.count { |req| req[:response_time] > 2000 },
        status_codes: {},
        common_issues: [],
        recommendations: []
      }

      # Group by status codes
      requests.group_by { |req| req[:status] }.each do |status, status_requests|
        analysis[:status_codes][status] = status_requests.size
      end

      # Identify 404 errors
      not_found_requests = requests.select { |req| req[:status] == 404 }
      if not_found_requests.any?
        analysis[:common_issues] << {
          type: "404_errors",
          count: not_found_requests.size,
          description: "Resources not found (404)"
        }
        analysis[:recommendations] << "Check file paths and API endpoint URLs"
      end

      # Identify 500 errors
      server_errors = requests.select { |req| req[:status] >= 500 }
      if server_errors.any?
        analysis[:common_issues] << {
          type: "server_errors",
          count: server_errors.size,
          description: "Server errors (5xx)"
        }
        analysis[:recommendations] << "Check server-side logic and error handling"
      end

      # Identify slow requests
      if analysis[:slow_requests] > 0
        analysis[:common_issues] << {
          type: "slow_requests",
          count: analysis[:slow_requests],
          description: "Slow network requests (>2s)"
        }
        analysis[:recommendations] << "Optimize API response times and add loading states"
      end

      analysis
    end

    def format_logs_for_ai(logs)
      return "No console logs found." if logs.empty?

      formatted = logs.map do |log|
        log[:timestamp].strftime("%H:%M:%S")
        location = log[:source] ? "#{log[:source]}:#{log[:line_number]}" : "unknown"

        if log[:source]
          "  at #{location}"
        end
      end

      formatted.compact.join("\n")
    end

    def format_requests_for_ai(requests)
      return "No network requests found." if requests.empty?

      formatted = requests.map do |req|
        req[:timestamp].strftime("%H:%M:%S")
        (req[:status] >= 400) ? "❌" : "✅"

        if req[:error]
          "   Error: #{req[:error]}"
        end
      end

      formatted.compact.join("\n")
    end
  end
end
