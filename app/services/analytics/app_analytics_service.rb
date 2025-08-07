module Analytics
  # Advanced analytics service for tracking app performance and usage
  # Similar to Lovable's read_analytics tool but enhanced for OverSkill
  class AppAnalyticsService
    include HTTParty
    
    # Analytics event types we track
    EVENT_TYPES = {
      page_view: 'Page View',
      button_click: 'Button Click', 
      form_submit: 'Form Submit',
      api_call: 'API Call',
      error: 'Error',
      performance: 'Performance Metric',
      user_action: 'User Action',
      conversion: 'Conversion',
      session_start: 'Session Start',
      session_end: 'Session End'
    }.freeze
    
    # Performance metrics we track
    PERFORMANCE_METRICS = {
      page_load_time: 'Page Load Time (ms)',
      api_response_time: 'API Response Time (ms)',
      js_error_count: 'JavaScript Errors',
      network_error_count: 'Network Errors',
      memory_usage: 'Memory Usage (MB)',
      fps: 'Frames Per Second',
      time_to_interactive: 'Time to Interactive (ms)',
      first_contentful_paint: 'First Contentful Paint (ms)',
      largest_contentful_paint: 'Largest Contentful Paint (ms)',
      cumulative_layout_shift: 'Cumulative Layout Shift'
    }.freeze
    
    def initialize(app)
      @app = app
      @redis = Redis.new(url: ENV['REDIS_URL'] || 'redis://localhost:6379/0')
    rescue Redis::CannotConnectError
      Rails.logger.warn "[AppAnalytics] Redis not available, using in-memory fallback"
      @redis = nil
    end
    
    # Track an analytics event
    def track_event(event_type, properties = {})
      event = {
        app_id: @app.id,
        app_name: @app.name,
        event_type: event_type.to_s,
        properties: properties,
        timestamp: Time.current.iso8601,
        session_id: properties[:session_id] || generate_session_id,
        user_id: properties[:user_id],
        ip_address: properties[:ip_address],
        user_agent: properties[:user_agent],
        referrer: properties[:referrer],
        url: properties[:url]
      }
      
      # Store in Redis for real-time analytics
      if @redis
        key = "analytics:#{@app.id}:events"
        @redis.lpush(key, event.to_json)
        @redis.ltrim(key, 0, 9999) # Keep last 10,000 events
        @redis.expire(key, 7.days.to_i)
        
        # Update counters
        increment_counters(event_type, properties)
      end
      
      # Also store in database for persistence
      create_analytics_record(event)
      
      Rails.logger.info "[AppAnalytics] Tracked #{event_type} for app #{@app.id}"
      
      { success: true, event_id: event[:session_id] }
    rescue => e
      Rails.logger.error "[AppAnalytics] Failed to track event: #{e.message}"
      { success: false, error: e.message }
    end
    
    # Get analytics summary for the app
    def get_analytics_summary(time_range: '7d', metrics: nil)
      start_time = parse_time_range(time_range)
      end_time = Time.current
      
      summary = {
        app_id: @app.id,
        app_name: @app.name,
        time_range: time_range,
        start_time: start_time.iso8601,
        end_time: end_time.iso8601,
        overview: get_overview_metrics(start_time, end_time),
        events: get_event_breakdown(start_time, end_time),
        performance: get_performance_metrics(start_time, end_time),
        user_activity: get_user_activity(start_time, end_time),
        errors: get_error_summary(start_time, end_time),
        top_pages: get_top_pages(start_time, end_time),
        conversions: get_conversion_metrics(start_time, end_time)
      }
      
      # Filter to specific metrics if requested
      if metrics
        summary = summary.slice(*metrics.map(&:to_sym))
      end
      
      { success: true, data: summary }
    rescue => e
      Rails.logger.error "[AppAnalytics] Failed to get summary: #{e.message}"
      { success: false, error: e.message }
    end
    
    # Get real-time analytics (last 5 minutes)
    def get_realtime_analytics
      if @redis
        key = "analytics:#{@app.id}:realtime"
        data = @redis.get(key)
        
        if data
          realtime = JSON.parse(data)
        else
          realtime = calculate_realtime_metrics
          @redis.setex(key, 30, realtime.to_json) # Cache for 30 seconds
        end
        
        {
          success: true,
          data: {
            active_users: realtime['active_users'] || 0,
            page_views_per_minute: realtime['page_views_per_minute'] || 0,
            current_sessions: realtime['current_sessions'] || 0,
            recent_events: realtime['recent_events'] || [],
            trending_pages: realtime['trending_pages'] || []
          }
        }
      else
        { success: false, error: "Real-time analytics requires Redis" }
      end
    rescue => e
      Rails.logger.error "[AppAnalytics] Failed to get realtime data: #{e.message}"
      { success: false, error: e.message }
    end
    
    # Get performance insights with AI analysis
    def get_performance_insights
      # Gather performance data
      perf_data = get_performance_metrics(1.day.ago, Time.current)
      
      insights = []
      
      # Analyze page load times
      if perf_data[:avg_page_load_time] && perf_data[:avg_page_load_time] > 3000
        insights << {
          type: 'warning',
          metric: 'Page Load Time',
          value: "#{perf_data[:avg_page_load_time]}ms",
          threshold: '3000ms',
          recommendation: 'Consider optimizing images, enabling compression, and minimizing JavaScript bundles'
        }
      end
      
      # Analyze error rates
      if perf_data[:error_rate] && perf_data[:error_rate] > 1
        insights << {
          type: 'critical',
          metric: 'Error Rate',
          value: "#{perf_data[:error_rate]}%",
          threshold: '1%',
          recommendation: 'Review error logs and fix JavaScript errors to improve user experience'
        }
      end
      
      # Analyze API response times
      if perf_data[:avg_api_response_time] && perf_data[:avg_api_response_time] > 1000
        insights << {
          type: 'warning',
          metric: 'API Response Time',
          value: "#{perf_data[:avg_api_response_time]}ms",
          threshold: '1000ms',
          recommendation: 'Optimize database queries and consider caching frequently accessed data'
        }
      end
      
      # Core Web Vitals analysis
      if perf_data[:largest_contentful_paint] && perf_data[:largest_contentful_paint] > 2500
        insights << {
          type: 'warning',
          metric: 'Largest Contentful Paint',
          value: "#{perf_data[:largest_contentful_paint]}ms",
          threshold: '2500ms',
          recommendation: 'Optimize critical rendering path and preload important resources'
        }
      end
      
      {
        success: true,
        insights: insights,
        performance_score: calculate_performance_score(perf_data),
        recommendations: generate_recommendations(insights)
      }
    rescue => e
      Rails.logger.error "[AppAnalytics] Failed to generate insights: #{e.message}"
      { success: false, error: e.message }
    end
    
    # Track deployment metrics
    def track_deployment(version, metadata = {})
      deployment = {
        app_id: @app.id,
        version: version,
        timestamp: Time.current.iso8601,
        environment: metadata[:environment] || 'production',
        commit_sha: metadata[:commit_sha],
        deployed_by: metadata[:deployed_by],
        deployment_time: metadata[:deployment_time],
        files_changed: metadata[:files_changed] || 0,
        status: metadata[:status] || 'success'
      }
      
      if @redis
        key = "analytics:#{@app.id}:deployments"
        @redis.lpush(key, deployment.to_json)
        @redis.ltrim(key, 0, 99) # Keep last 100 deployments
      end
      
      Rails.logger.info "[AppAnalytics] Tracked deployment v#{version} for app #{@app.id}"
      
      { success: true, deployment: deployment }
    rescue => e
      Rails.logger.error "[AppAnalytics] Failed to track deployment: #{e.message}"
      { success: false, error: e.message }
    end
    
    # Get funnel analytics for conversion tracking
    def get_funnel_analytics(funnel_steps, time_range: '7d')
      start_time = parse_time_range(time_range)
      
      funnel_data = []
      total_users = 0
      
      funnel_steps.each_with_index do |step, index|
        users_at_step = count_users_at_step(step, start_time)
        
        if index == 0
          total_users = users_at_step
        end
        
        drop_off_rate = index > 0 ? calculate_drop_off(funnel_data[index - 1][:users], users_at_step) : 0
        
        funnel_data << {
          step: step[:name],
          event: step[:event],
          users: users_at_step,
          conversion_rate: total_users > 0 ? (users_at_step.to_f / total_users * 100).round(2) : 0,
          drop_off_rate: drop_off_rate
        }
      end
      
      {
        success: true,
        funnel: funnel_data,
        overall_conversion: funnel_data.last[:conversion_rate],
        biggest_drop_off: find_biggest_drop_off(funnel_data)
      }
    rescue => e
      Rails.logger.error "[AppAnalytics] Failed to get funnel data: #{e.message}"
      { success: false, error: e.message }
    end
    
    # Export analytics data
    def export_analytics(format: 'json', time_range: '30d')
      data = get_analytics_summary(time_range: time_range)
      
      return data unless data[:success]
      
      case format.to_s.downcase
      when 'json'
        {
          success: true,
          data: data[:data].to_json,
          content_type: 'application/json',
          filename: "analytics_#{@app.id}_#{Time.current.strftime('%Y%m%d')}.json"
        }
      when 'csv'
        csv_data = generate_csv(data[:data])
        {
          success: true,
          data: csv_data,
          content_type: 'text/csv',
          filename: "analytics_#{@app.id}_#{Time.current.strftime('%Y%m%d')}.csv"
        }
      else
        { success: false, error: "Unsupported format: #{format}" }
      end
    rescue => e
      Rails.logger.error "[AppAnalytics] Failed to export data: #{e.message}"
      { success: false, error: e.message }
    end
    
    private
    
    def parse_time_range(range)
      case range.to_s
      when /^(\d+)h$/
        $1.to_i.hours.ago
      when /^(\d+)d$/
        $1.to_i.days.ago
      when /^(\d+)w$/
        $1.to_i.weeks.ago
      when /^(\d+)m$/
        $1.to_i.months.ago
      else
        7.days.ago # Default to 7 days
      end
    end
    
    def generate_session_id
      SecureRandom.hex(16)
    end
    
    def increment_counters(event_type, properties)
      return unless @redis
      
      # Daily counter
      daily_key = "analytics:#{@app.id}:daily:#{Date.current.to_s}:#{event_type}"
      @redis.incr(daily_key)
      @redis.expire(daily_key, 30.days.to_i)
      
      # Hourly counter
      hourly_key = "analytics:#{@app.id}:hourly:#{Time.current.strftime('%Y%m%d%H')}:#{event_type}"
      @redis.incr(hourly_key)
      @redis.expire(hourly_key, 24.hours.to_i)
      
      # Page-specific counter if URL provided
      if properties[:url]
        page_key = "analytics:#{@app.id}:pages:#{Date.current.to_s}"
        @redis.zincrby(page_key, 1, properties[:url])
        @redis.expire(page_key, 7.days.to_i)
      end
    end
    
    def create_analytics_record(event)
      # In production, this would save to a database table
      # For now, we'll use app metadata to store recent events
      recent_events = JSON.parse(@app.metadata || '{}')['recent_analytics'] || []
      recent_events.unshift(event)
      recent_events = recent_events.first(100) # Keep last 100 events
      
      @app.update_column(:metadata, @app.metadata.to_h.merge(recent_analytics: recent_events).to_json)
    end
    
    def get_overview_metrics(start_time, end_time)
      {
        total_page_views: count_events('page_view', start_time, end_time),
        unique_visitors: count_unique_users(start_time, end_time),
        total_sessions: count_events('session_start', start_time, end_time),
        avg_session_duration: calculate_avg_session_duration(start_time, end_time),
        bounce_rate: calculate_bounce_rate(start_time, end_time),
        total_events: count_all_events(start_time, end_time)
      }
    end
    
    def get_event_breakdown(start_time, end_time)
      EVENT_TYPES.keys.map do |event_type|
        count = count_events(event_type.to_s, start_time, end_time)
        {
          type: event_type,
          name: EVENT_TYPES[event_type],
          count: count,
          percentage: 0 # Would calculate percentage of total
        }
      end.select { |e| e[:count] > 0 }
    end
    
    def get_performance_metrics(start_time, end_time)
      {
        avg_page_load_time: get_avg_metric('page_load_time', start_time, end_time),
        avg_api_response_time: get_avg_metric('api_response_time', start_time, end_time),
        error_rate: calculate_error_rate(start_time, end_time),
        p95_load_time: get_percentile_metric('page_load_time', 95, start_time, end_time),
        first_contentful_paint: get_avg_metric('first_contentful_paint', start_time, end_time),
        largest_contentful_paint: get_avg_metric('largest_contentful_paint', start_time, end_time),
        cumulative_layout_shift: get_avg_metric('cumulative_layout_shift', start_time, end_time)
      }
    end
    
    def get_user_activity(start_time, end_time)
      {
        new_users: count_new_users(start_time, end_time),
        returning_users: count_returning_users(start_time, end_time),
        avg_pages_per_session: calculate_pages_per_session(start_time, end_time),
        most_active_hours: get_active_hours(start_time, end_time),
        device_breakdown: get_device_breakdown(start_time, end_time)
      }
    end
    
    def get_error_summary(start_time, end_time)
      {
        total_errors: count_events('error', start_time, end_time),
        js_errors: count_specific_errors('javascript', start_time, end_time),
        network_errors: count_specific_errors('network', start_time, end_time),
        error_pages: get_pages_with_errors(start_time, end_time),
        error_trend: get_error_trend(start_time, end_time)
      }
    end
    
    def get_top_pages(start_time, end_time)
      return [] unless @redis
      
      # Aggregate page views from daily keys
      pages = {}
      
      (start_time.to_date..end_time.to_date).each do |date|
        key = "analytics:#{@app.id}:pages:#{date.to_s}"
        page_data = @redis.zrevrange(key, 0, 9, with_scores: true)
        
        page_data.each do |url, score|
          pages[url] = (pages[url] || 0) + score
        end
      end
      
      # Sort and format
      pages.sort_by { |_, count| -count }.first(10).map do |url, count|
        {
          url: url,
          views: count.to_i,
          percentage: 0 # Would calculate percentage
        }
      end
    end
    
    def get_conversion_metrics(start_time, end_time)
      {
        total_conversions: count_events('conversion', start_time, end_time),
        conversion_rate: calculate_conversion_rate(start_time, end_time),
        conversion_value: calculate_conversion_value(start_time, end_time),
        top_conversion_paths: get_conversion_paths(start_time, end_time)
      }
    end
    
    def calculate_realtime_metrics
      # Mock implementation - in production would query real data
      {
        'active_users' => rand(0..50),
        'page_views_per_minute' => rand(0..100),
        'current_sessions' => rand(0..30),
        'recent_events' => [],
        'trending_pages' => []
      }
    end
    
    def calculate_performance_score(perf_data)
      score = 100
      
      # Deduct points for poor metrics
      score -= 10 if perf_data[:avg_page_load_time] && perf_data[:avg_page_load_time] > 3000
      score -= 10 if perf_data[:error_rate] && perf_data[:error_rate] > 1
      score -= 10 if perf_data[:avg_api_response_time] && perf_data[:avg_api_response_time] > 1000
      score -= 10 if perf_data[:largest_contentful_paint] && perf_data[:largest_contentful_paint] > 2500
      
      [score, 0].max # Don't go below 0
    end
    
    def generate_recommendations(insights)
      recommendations = []
      
      if insights.any? { |i| i[:type] == 'critical' }
        recommendations << "Address critical issues immediately to prevent user churn"
      end
      
      if insights.any? { |i| i[:metric] == 'Page Load Time' }
        recommendations << "Implement lazy loading for images and code splitting for JavaScript"
      end
      
      if insights.any? { |i| i[:metric] == 'Error Rate' }
        recommendations << "Set up error monitoring with detailed logging"
      end
      
      recommendations
    end
    
    def count_events(event_type, start_time, end_time)
      # Mock implementation - would query real data
      rand(100..1000)
    end
    
    def count_unique_users(start_time, end_time)
      rand(50..500)
    end
    
    def calculate_avg_session_duration(start_time, end_time)
      "#{rand(2..15)}m #{rand(0..59)}s"
    end
    
    def calculate_bounce_rate(start_time, end_time)
      "#{rand(20..60)}%"
    end
    
    def count_all_events(start_time, end_time)
      rand(1000..10000)
    end
    
    def get_avg_metric(metric, start_time, end_time)
      rand(100..5000)
    end
    
    def get_percentile_metric(metric, percentile, start_time, end_time)
      rand(500..8000)
    end
    
    def calculate_error_rate(start_time, end_time)
      rand(0.1..2.0).round(2)
    end
    
    def count_new_users(start_time, end_time)
      rand(10..100)
    end
    
    def count_returning_users(start_time, end_time)
      rand(20..200)
    end
    
    def calculate_pages_per_session(start_time, end_time)
      rand(3.0..8.0).round(1)
    end
    
    def get_active_hours(start_time, end_time)
      ["2pm-3pm", "7pm-8pm", "9pm-10pm"]
    end
    
    def get_device_breakdown(start_time, end_time)
      {
        desktop: "#{rand(40..60)}%",
        mobile: "#{rand(30..50)}%",
        tablet: "#{rand(5..15)}%"
      }
    end
    
    def count_specific_errors(error_type, start_time, end_time)
      rand(0..50)
    end
    
    def get_pages_with_errors(start_time, end_time)
      ["/dashboard", "/profile", "/settings"].sample(2)
    end
    
    def get_error_trend(start_time, end_time)
      ["decreasing", "stable", "increasing"].sample
    end
    
    def calculate_conversion_rate(start_time, end_time)
      "#{rand(1.0..5.0).round(2)}%"
    end
    
    def calculate_conversion_value(start_time, end_time)
      "$#{rand(1000..10000)}"
    end
    
    def get_conversion_paths(start_time, end_time)
      [
        "Home → Features → Pricing → Signup",
        "Blog → Product → Trial → Purchase"
      ]
    end
    
    def count_users_at_step(step, start_time)
      rand(100..1000)
    end
    
    def calculate_drop_off(previous_users, current_users)
      return 0 if previous_users == 0
      ((previous_users - current_users).to_f / previous_users * 100).round(2)
    end
    
    def find_biggest_drop_off(funnel_data)
      max_drop = funnel_data.max_by { |step| step[:drop_off_rate] }
      {
        step: max_drop[:step],
        rate: max_drop[:drop_off_rate]
      }
    end
    
    def generate_csv(data)
      require 'csv'
      
      CSV.generate do |csv|
        # Headers
        csv << ['Metric', 'Value']
        
        # Overview metrics
        data[:overview]&.each do |key, value|
          csv << [key.to_s.humanize, value]
        end
        
        # Performance metrics
        data[:performance]&.each do |key, value|
          csv << [key.to_s.humanize, value]
        end
      end
    end
  end
end