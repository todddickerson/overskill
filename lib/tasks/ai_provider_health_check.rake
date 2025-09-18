namespace :ai do
  desc "Test OpenRouter + Kimi K2 tool calling status and update feature flags"
  task health_check: :environment do
    puts "🏥 AI Provider Health Check - #{Time.current}"
    puts "=" * 60

    # Run the tool calling test
    require_relative "../../scripts/test_openrouter_kimi_tool_calling"

    tester = OpenRouterKimiToolCallTest.new
    results = tester.run_all_tests

    # Update feature flag based on results
    update_feature_flag(results)

    # Send alerts if status changed
    check_for_status_changes(results)

    puts "\n✅ Health check completed"
  end

  desc "Enable OpenRouter tool calling (manual override)"
  task enable_openrouter_tool_calling: :environment do
    flag = FeatureFlag.find_or_create_by(name: "openrouter_kimi_tool_calling")
    flag.update!(enabled: true, percentage: 100)
    puts "✅ OpenRouter tool calling enabled (manual override)"
  end

  desc "Disable OpenRouter tool calling (manual override)"
  task disable_openrouter_tool_calling: :environment do
    flag = FeatureFlag.find_or_create_by(name: "openrouter_kimi_tool_calling")
    flag.update!(enabled: false, percentage: 0)
    puts "✅ OpenRouter tool calling disabled (manual override)"
  end

  desc "Show current AI provider status"
  task provider_status: :environment do
    puts "🔍 Current AI Provider Status"
    puts "=" * 40

    # Feature flags
    openrouter_flag = FeatureFlag.find_by(name: "openrouter_kimi_tool_calling")
    puts "OpenRouter Tool Calling: #{openrouter_flag&.enabled? ? "✅ Enabled" : "❌ Disabled"}"
    puts "Rollout Percentage: #{openrouter_flag&.percentage || 0}%"

    # Recent test results
    log_dir = Rails.root.join("log", "tool_calling_tests")
    if log_dir.exist?
      recent_file = Dir.glob(log_dir.join("*_openrouter_kimi_test.json"))
        .max_by { |f| File.mtime(f) }

      if recent_file && File.mtime(recent_file) > 24.hours.ago
        results = JSON.parse(File.read(recent_file))
        timestamp = Time.parse(results["timestamp"])
        working = results.dig("summary", "tool_calls_working")

        puts "\nLast Test: #{timestamp.strftime("%Y-%m-%d %H:%M:%S")}"
        puts "Tool Calling Status: #{working ? "✅ Working" : "❌ Not Working"}"
        puts "Tests Passed: #{results.dig("summary", "passed")}/#{results.dig("summary", "total")}"
      else
        puts "\n⚠️  No recent test results (run `rake ai:health_check`)"
      end
    else
      puts "\n⚠️  No test results found (run `rake ai:health_check`)"
    end

    # Cost implications
    puts "\nCost Impact:"
    if Ai::ProviderSelectorService.tool_calling_available_via_openrouter?
      puts "💰 Using OpenRouter (cost savings: ~96% vs direct Moonshot)"
    else
      puts "💸 Using direct Moonshot API (28x more expensive but reliable)"
    end
  end

  private

  def update_feature_flag(results)
    flag = FeatureFlag.find_or_create_by(name: "openrouter_kimi_tool_calling")
    old_status = flag.enabled?
    new_status = results[:summary][:tool_calls_working]

    if old_status != new_status
      if new_status
        # Tool calling is working - enable with gradual rollout
        flag.update!(enabled: true, percentage: 10)  # Start with 10%
        puts "\n🎉 OpenRouter tool calling is now working! Enabled for 10% of users."
      else
        # Tool calling broken - disable
        flag.update!(enabled: false, percentage: 0)
        puts "\n⚠️  OpenRouter tool calling is broken. Disabled feature flag."
      end
    else
      puts "\n📊 Feature flag status unchanged (#{new_status ? "enabled" : "disabled"})"
    end
  end

  def check_for_status_changes(results)
    # Check if we should send alerts
    status_file = Rails.root.join("tmp", "ai_provider_status.json")

    current_status = {
      tool_calling_working: results[:summary][:tool_calls_working],
      timestamp: results[:timestamp]
    }

    if File.exist?(status_file)
      begin
        previous_status = JSON.parse(File.read(status_file))

        if previous_status["tool_calling_working"] != current_status[:tool_calling_working]
          send_status_change_alert(previous_status["tool_calling_working"], current_status[:tool_calls_working])
        end
      rescue => e
        Rails.logger.warn "Failed to read previous status: #{e.message}"
      end
    end

    # Save current status
    File.write(status_file, JSON.pretty_generate(current_status))
  end

  def send_status_change_alert(old_status, new_status)
    message = if new_status
      "🎉 OpenRouter + Kimi K2 tool calling is now WORKING! Consider gradual rollout to save costs."
    else
      "⚠️ OpenRouter + Kimi K2 tool calling has STOPPED working. Falling back to direct Moonshot API."
    end

    Rails.logger.info "[AI Provider Alert] #{message}"

    # Send to monitoring service, Slack, email, etc.
    # AlertService.send_ai_provider_alert(message) if defined?(AlertService)

    puts "\n🚨 STATUS CHANGE ALERT: #{message}"
  end
end
