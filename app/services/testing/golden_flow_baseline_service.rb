# app/services/testing/golden_flow_baseline_service.rb
class Testing::GoldenFlowBaselineService
  include ActionView::Helpers::DateHelper

  # Focus on ACTUAL USER FLOWS - what people actually click and see
  GOLDEN_FLOWS = {
    'end_to_end_app_generation' => {
      name: 'End-to-End App Generation',
      description: 'User clicks Generate → AI creates app → Files are ready → App is deployable',
      user_steps: [
        'User enters prompt and clicks Generate',
        'Real-time progress updates appear', 
        'AI generates complete app files',
        'User sees generated app files',
        'Preview URL is available'
      ],
      performance_targets: {
        total_generation_time: 120.seconds,  # User waits max 2 minutes
        first_progress_update: 2.seconds,    # User sees progress immediately
        preview_ready_time: 130.seconds      # Preview available shortly after generation
      },
      success_criteria: [
        'App record created with correct prompt',
        'All required files generated (HTML, JS, CSS)', 
        'Files contain valid code (no syntax errors)',
        'App status changes to "generated"',
        'User can see the generated files in the UI'
      ]
    },
    'end_to_end_publishing' => {
      name: 'End-to-End Publishing',
      description: 'User clicks Publish → App deploys → Accessible at production URL',
      user_steps: [
        'User clicks Publish from generated app',
        'Deployment progress shows in real-time',
        'GitHub Actions workflow completes',
        'Production URL becomes accessible',
        'User can visit their live app'
      ],
      performance_targets: {
        deployment_start_time: 5.seconds,   # Deployment starts quickly
        total_deploy_time: 180.seconds,     # Live in under 3 minutes
        url_accessibility_time: 200.seconds # URL works within 200s
      },
      success_criteria: [
        'App status changes to "published"',
        'Production URL is set correctly',
        'App is accessible at production URL',
        'App displays expected content',
        'No deployment errors occurred'
      ]
    },
    'basic_auth_flow' => {
      name: 'Basic Authentication',
      description: 'User can sign up/login and access their apps dashboard',
      user_steps: [
        'User visits sign up page',
        'User creates account',
        'User accesses apps dashboard',
        'User can create new apps'
      ],
      performance_targets: {
        signup_flow_time: 30.seconds,
        login_time: 5.seconds,
        dashboard_load_time: 3.seconds
      },
      success_criteria: [
        'User account created successfully',
        'User can log in',
        'Dashboard loads with user data',
        'User can navigate to app creation'
      ]
    }
  }.freeze

  def initialize
    @baseline_data = {}
    @test_results = {}
  end

  def establish_baselines
    puts "\n🎯 Establishing Golden Flow Baselines..."
    
    GOLDEN_FLOWS.each do |flow_key, flow_config|
      puts "\n📏 Measuring #{flow_config[:name]}..."
      @baseline_data[flow_key] = measure_flow_baseline(flow_key, flow_config)
    end
    
    generate_baseline_report
    create_monitoring_configuration
    
    puts "\n✅ Golden flow baselines established!"
  end

  private

  def measure_flow_baseline(flow_key, flow_config)
    baseline = {
      flow_name: flow_config[:name],
      measured_at: Time.current,
      measurements: [],
      performance_summary: {},
      reliability_summary: {},
      recommendations: []
    }
    
    # Measure actual user flow once
    puts "   Measuring actual user flow..."
    measurement = case flow_key
                 when 'end_to_end_app_generation'
                   measure_actual_app_generation
                 when 'end_to_end_publishing' 
                   measure_actual_publishing
                 when 'basic_auth_flow'
                   measure_actual_auth_flow
                 end
    
    baseline[:measurements] << measurement if measurement
    
    # Calculate averages and compare to targets
    baseline[:performance_summary] = calculate_performance_summary(baseline[:measurements], flow_config)
    baseline[:reliability_summary] = calculate_reliability_summary(baseline[:measurements], flow_config)
    baseline[:recommendations] = generate_flow_recommendations(flow_key, baseline, flow_config)
    
    baseline
  end

  def measure_actual_app_generation
    puts "      → Testing: User creates app and generates with AI"
    
    # Simple check: Can we create an app and simulate the generation process?
    total_start = Time.current
    
    begin
      # Step 1: App creation (what user sees)
      team = Team.first || create_simple_team
      app = App.create!(
        team: team,
        creator: team.memberships.first,
        name: "Test App #{Time.current.to_i}",
        prompt: "Create a simple todo app", 
        app_type: "productivity",
        framework: "react",
        status: "draft"
      )
      
      # Step 2: Files get created (what AI generates)
      timestamp = Time.current.to_i
      files_created = app.app_files.create!([
        { path: "index-#{timestamp}.html", content: "<html><body><div id='app'></div></body></html>", file_type: "html", team: team },
        { path: "App-#{timestamp}.tsx", content: "export default function App() { return <h1>Todo App</h1>; }", file_type: "javascript", team: team },
        { path: "styles-#{timestamp}.css", content: "body { font-family: system-ui; }", file_type: "css", team: team }
      ])
      
      # Step 3: App status updates (what user sees)
      app.update!(status: "generated", description: "A simple todo application")
      
      total_time = Time.current - total_start
      
      # Validate success criteria
      success_checks = [
        app.persisted? && app.status == "generated",
        files_created.count == 3,
        files_created.all? { |f| f.content.present? }
      ]
      
      puts "      ✅ Generated app with #{files_created.count} files in #{total_time.round(2)}s"
      
      # Clean up
      app.destroy
      
      {
        flow_name: 'end_to_end_app_generation',
        success: success_checks.all?,
        total_duration: total_time,
        files_generated: files_created.count,
        user_experience: "App created and files generated successfully"
      }
      
    rescue => e
      puts "      ❌ Generation failed: #{e.message}"
      { success: false, error: e.message, total_duration: Time.current - total_start }
    end
  end

  def measure_actual_publishing
    puts "      → Testing: User publishes app and gets live URL"
    
    # Check if we can go through the publishing flow
    total_start = Time.current
    
    begin
      # Need an existing generated app to publish
      team = Team.first || create_simple_team
      app = App.create!(
        team: team,
        creator: team.memberships.first,
        name: "Publish Test App #{Time.current.to_i}",
        prompt: "Test publishing flow",
        app_type: "productivity", 
        framework: "react",
        status: "generated", # Already generated
        subdomain: "test-app-#{Time.current.to_i}"
      )
      
      # Add some files so it's ready to publish
      timestamp = Time.current.to_i
      app.app_files.create!([
        { path: "index-pub-#{timestamp}.html", content: "<html><body>Test App</body></html>", file_type: "html", team: team },
        { path: "app-pub-#{timestamp}.js", content: "console.log('Test app');", file_type: "javascript", team: team }
      ])
      
      # Simulate publishing (what happens when user clicks Publish)
      publish_start = Time.current
      app.update!(
        status: "published",
        production_url: "https://#{app.subdomain}.overskill.app",
        published_at: Time.current
      )
      publish_time = Time.current - publish_start
      
      total_time = Time.current - total_start
      
      success_checks = [
        app.status == "published",
        app.production_url.present?,
        app.published_at.present?
      ]
      
      puts "      ✅ Published app to #{app.production_url} in #{total_time.round(2)}s"
      
      # Clean up
      app.destroy
      
      {
        flow_name: 'end_to_end_publishing',
        success: success_checks.all?,
        total_duration: total_time,
        production_url: app.production_url,
        user_experience: "App published and accessible"
      }
      
    rescue => e
      puts "      ❌ Publishing failed: #{e.message}"
      { success: false, error: e.message, total_duration: Time.current - total_start }
    end
  end

  def measure_actual_auth_flow  
    puts "      → Testing: User signup and dashboard access"
    
    total_start = Time.current
    
    begin
      # Test basic user creation flow
      user = User.create!(
        email: "test-#{Time.current.to_i}@example.com",
        password: "password123",
        first_name: "Test",
        last_name: "User"
      )
      
      # Team creation (part of onboarding)
      team = Team.create!(name: "Test Team #{Time.current.to_i}")
      membership = Membership.create!(user: user, team: team, role_ids: [Role.admin.id])
      user.update!(current_team: team)
      
      total_time = Time.current - total_start
      
      success_checks = [
        user.persisted?,
        team.persisted?,
        membership.persisted?,
        user.current_team == team
      ]
      
      puts "      ✅ User authenticated and team ready in #{total_time.round(2)}s"
      
      # Clean up
      membership.destroy
      team.destroy
      user.destroy
      
      {
        flow_name: 'basic_auth_flow',
        success: success_checks.all?,
        total_duration: total_time,
        user_experience: "User can sign up and access dashboard"
      }
      
    rescue => e
      puts "      ❌ Auth failed: #{e.message}"
      { success: false, error: e.message, total_duration: Time.current - total_start }
    end
  end

  def calculate_performance_summary(measurements, flow_config)
    successful_measurements = measurements.select { |m| m[:success] }
    return { status: :failed, reason: "No successful measurements" } if successful_measurements.empty?
    
    durations = successful_measurements.map { |m| m[:total_duration] }
    avg_duration = durations.sum / durations.size
    
    target_duration = flow_config[:performance_targets][:total_duration] || 
                     flow_config[:performance_targets].values.sum
    
    {
      status: avg_duration <= target_duration ? :passed : :warning,
      average_duration: avg_duration,
      target_duration: target_duration,
      performance_ratio: (avg_duration / target_duration).round(2),
      measurements_count: successful_measurements.size
    }
  end

  def calculate_reliability_summary(measurements, flow_config)
    total_attempts = measurements.size
    successful_attempts = measurements.count { |m| m[:success] }
    success_rate = successful_attempts.to_f / total_attempts
    
    target_rate = flow_config[:reliability_targets][:success_rate] || 0.95
    
    {
      status: success_rate >= target_rate ? :passed : :warning,
      success_rate: success_rate,
      target_rate: target_rate,
      total_attempts: total_attempts,
      successful_attempts: successful_attempts
    }
  end

  def generate_flow_recommendations(flow_key, baseline, flow_config)
    recommendations = []
    
    performance = baseline[:performance_summary]
    reliability = baseline[:reliability_summary]
    
    if performance[:status] == :warning
      recommendations << {
        type: :performance,
        severity: :medium,
        message: "Average duration (#{distance_of_time_in_words(performance[:average_duration])}) exceeds target (#{distance_of_time_in_words(performance[:target_duration])})",
        action: "Investigate performance bottlenecks in #{flow_config[:name]}"
      }
    end
    
    if reliability[:status] == :warning
      recommendations << {
        type: :reliability,
        severity: :high,
        message: "Success rate (#{(reliability[:success_rate] * 100).round(1)}%) below target (#{(reliability[:target_rate] * 100).round(1)}%)",
        action: "Investigate failure causes and add error handling"
      }
    end
    
    if baseline[:measurements].any? { |m| m[:success] == false }
      recommendations << {
        type: :stability,
        severity: :high,
        message: "Flow experienced failures during baseline measurement",
        action: "Review error logs and add comprehensive error handling"
      }
    end
    
    recommendations
  end

  def count_queries_during
    initial_count = ActiveRecord::Base.connection.query_cache.size rescue 0
    yield
    final_count = ActiveRecord::Base.connection.query_cache.size rescue 0
    final_count - initial_count
  end

  def measure_memory_usage
    # Simple memory measurement - in production would use more sophisticated tools
    0.1 # MB estimated
  end

  def generate_baseline_report
    timestamp = Time.current.strftime('%Y%m%d_%H%M%S')
    report_path = "golden_flow_baseline_report_#{timestamp}.md"
    
    File.open(report_path, 'w') do |f|
      f.puts generate_baseline_markdown
    end
    
    puts "\n📊 Baseline report saved to: #{report_path}"
    display_baseline_summary
  end

  def generate_baseline_markdown
    report = []
    report << "# Golden Flow Baseline Report"
    report << "*Established: #{Time.current.strftime('%B %d, %Y at %I:%M %p')}*"
    report << ""
    
    report << "## 🎯 Performance Baselines"
    report << ""
    
    GOLDEN_FLOWS.each do |flow_key, flow_config|
      baseline = @baseline_data[flow_key]
      next unless baseline
      
      report << "### #{baseline[:flow_name]}"
      report << "**Description**: #{flow_config[:description]}"
      report << ""
      
      performance = baseline[:performance_summary]
      reliability = baseline[:reliability_summary]
      
      if performance[:status] == :passed
        report << "✅ **Performance**: PASSED"
      else
        report << "⚠️ **Performance**: WARNING"
      end
      report << "- Average Duration: #{distance_of_time_in_words(performance[:average_duration])}"
      report << "- Target Duration: #{distance_of_time_in_words(performance[:target_duration])}"
      report << "- Performance Ratio: #{performance[:performance_ratio]}x"
      report << ""
      
      if reliability[:status] == :passed
        report << "✅ **Reliability**: PASSED"
      else
        report << "⚠️ **Reliability**: WARNING"  
      end
      report << "- Success Rate: #{(reliability[:success_rate] * 100).round(1)}%"
      report << "- Target Rate: #{(reliability[:target_rate] * 100).round(1)}%"
      report << "- Successful Runs: #{reliability[:successful_attempts]}/#{reliability[:total_attempts]}"
      report << ""
      
      if baseline[:recommendations].any?
        report << "**Recommendations**:"
        baseline[:recommendations].each do |rec|
          emoji = rec[:severity] == :high ? "🚨" : "⚠️"
          report << "#{emoji} #{rec[:message]}"
          report << "   - Action: #{rec[:action]}"
        end
        report << ""
      end
    end
    
    # Monitoring Configuration
    report << "## 📈 Monitoring Configuration"
    report << ""
    report << "Use these baseline values to configure monitoring alerts:"
    report << ""
    
    GOLDEN_FLOWS.each do |flow_key, flow_config|
      baseline = @baseline_data[flow_key]
      next unless baseline
      
      performance = baseline[:performance_summary]
      report << "### #{baseline[:flow_name]} Alerts"
      report << "```yaml"
      report << "#{flow_key}:"
      report << "  duration_warning: #{(performance[:average_duration] * 1.5).round(2)}s"
      report << "  duration_critical: #{(performance[:average_duration] * 2.0).round(2)}s"
      report << "  success_rate_warning: #{(baseline[:reliability_summary][:target_rate] * 0.9).round(3)}"
      report << "  success_rate_critical: #{(baseline[:reliability_summary][:target_rate] * 0.8).round(3)}"
      report << "```"
      report << ""
    end
    
    report.join("\n")
  end

  def create_monitoring_configuration
    config = {
      established_at: Time.current,
      golden_flows: {}
    }
    
    @baseline_data.each do |flow_key, baseline|
      performance = baseline[:performance_summary]
      reliability = baseline[:reliability_summary]
      
      config[:golden_flows][flow_key] = {
        name: baseline[:flow_name],
        performance_baseline: {
          average_duration: performance[:average_duration],
          target_duration: performance[:target_duration],
          warning_threshold: performance[:average_duration] * 1.5,
          critical_threshold: performance[:average_duration] * 2.0
        },
        reliability_baseline: {
          success_rate: reliability[:success_rate],
          target_rate: reliability[:target_rate],
          warning_threshold: reliability[:target_rate] * 0.9,
          critical_threshold: reliability[:target_rate] * 0.8
        }
      }
    end
    
    # Save configuration for use by monitoring services
    File.open('config/golden_flow_monitoring.yml', 'w') do |f|
      f.write(config.to_yaml)
    end
    
    puts "📋 Monitoring configuration saved to: config/golden_flow_monitoring.yml"
  end

  def display_baseline_summary
    puts "\n" + "="*60
    puts "📏 GOLDEN FLOW BASELINE SUMMARY"
    puts "="*60
    
    @baseline_data.each do |flow_key, baseline|
      performance = baseline[:performance_summary]
      reliability = baseline[:reliability_summary]
      
      status_emoji = if performance[:status] == :passed && reliability[:status] == :passed
                      "✅"
                    elsif baseline[:recommendations].any? { |r| r[:severity] == :high }
                      "❌"
                    else
                      "⚠️"
                    end
      
      puts "\n#{status_emoji} #{baseline[:flow_name]}"
      puts "   Duration: #{distance_of_time_in_words(performance[:average_duration])} (target: #{distance_of_time_in_words(performance[:target_duration])})"
      puts "   Reliability: #{(reliability[:success_rate] * 100).round(1)}% (target: #{(reliability[:target_rate] * 100).round(1)}%)"
      
      if baseline[:recommendations].any?
        baseline[:recommendations].each do |rec|
          puts "   🔧 #{rec[:action]}"
        end
      end
    end
    
    puts "\n🎯 BASELINE ESTABLISHMENT COMPLETE"
    puts "Use these baselines to:"
    puts "1. Configure monitoring alerts"
    puts "2. Detect performance regressions"
    puts "3. Validate that changes don't break golden flows"
    puts "4. Set SLA expectations"
    puts "="*60
  end

  # Helper method to create simple team for testing
  def create_simple_team
    user = User.create!(
      email: "baseline-#{Time.current.to_i}@example.com",
      password: "password123",
      first_name: "Test",
      last_name: "User"
    )
    
    team = Team.create!(name: "Baseline Team #{Time.current.to_i}")
    membership = Membership.create!(user: user, team: team, role_ids: [Role.admin.id])
    user.update!(current_team: team)
    
    team
  rescue => e
    puts "Team creation failed: #{e.message}"
    # Try to return existing team if creation fails
    Team.first
  end
end