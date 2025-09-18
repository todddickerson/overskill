namespace :helicone do
  desc "Check Helicone integration status and test connection"
  task status: :environment do
    client = Ai::AnthropicClient.instance

    puts "=" * 50
    puts "Helicone Integration Status"
    puts "=" * 50

    if client.helicone_enabled?
      puts "✅ Status: ENABLED"
      puts "🔑 API Key: #{ENV["HELICONE_API_KEY"].present? ? "Set" : "Missing"}"

      info = client.helicone_info
      puts "🌐 Endpoint: #{info[:api_endpoint]}"
      puts "📊 Dashboard: #{info[:dashboard_url]}"
      puts "🚀 Features: #{info[:features].join(", ")}"

      puts "\n📝 Testing basic API call with Helicone..."

      begin
        response = client.chat([
          {role: "user", content: "Say 'Hello from OverSkill via Helicone!'"}
        ])

        if response[:success]
          puts "✅ Test successful!"
          puts "💬 Response: #{response[:content]}"
          puts "📈 Usage: #{response[:usage].inspect}"

          if response[:usage]
            puts "💰 Cost tracking available through Helicone dashboard"
          end
        else
          puts "❌ Test failed: #{response[:error]}"
        end
      rescue => e
        puts "❌ Error: #{e.message}"
      end
    else
      puts "⚠️  Status: DISABLED"
      puts "💡 To enable: Set HELICONE_API_KEY in .env.local"
      puts "🔗 Get API key: https://app.helicone.ai/signup"
      puts "\n📋 Benefits of enabling Helicone:"
      puts "   • Real-time observability and analytics"
      puts "   • Request/response logging and debugging"
      puts "   • Cost tracking and optimization insights"
      puts "   • Performance monitoring and alerting"
      puts "   • Session tracking for multi-turn conversations"
    end

    puts "\n" + "=" * 50
  end

  desc "Check context window capabilities"
  task context_info: :environment do
    client = Ai::AnthropicClient.instance
    info = client.context_window_info

    puts "=" * 50
    puts "Claude Context Window Information"
    puts "=" * 50

    puts "📏 Standard Context Window: #{info[:standard_window].to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} tokens"
    puts "🧪 Beta Context Window: #{info[:beta_window].to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} tokens"
    puts "🎯 Beta Activation Threshold: #{info[:beta_activation_threshold].to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} tokens"

    if info[:has_beta_access]
      puts "✅ 1M Context Window: AVAILABLE"
      puts "📈 Beta Rate Limits:"
      puts "   • Input: #{info[:beta_rate_limits][:input_tokens_per_min].to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} tokens/min"
      puts "   • Output: #{info[:beta_rate_limits][:output_tokens_per_min].to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse} tokens/min"
    else
      puts "❌ 1M Context Window: NOT AVAILABLE"
      puts "💡 How to get beta access:"
      puts "   • High-usage account or enterprise customer"
      puts "   • Contact Anthropic support for beta access"
      puts "   • Email: support@anthropic.com"
      puts "   • Mention: '1M context window beta access request'"
    end

    puts "\n🔗 Documentation: https://docs.anthropic.com/en/docs/build-with-claude/context-windows"
    puts "🧪 Test: rails helicone:test_1m_context"
    puts "=" * 50
  end

  desc "Test Helicone caching with a repeated request"
  task test_cache: :environment do
    unless Ai::AnthropicClient.instance.helicone_enabled?
      puts "❌ Helicone is not enabled. Set HELICONE_API_KEY first."
      exit 1
    end

    client = Ai::AnthropicClient.instance
    test_message = "What is the capital of France? Please respond with just the city name."

    puts "🧪 Testing Helicone caching with identical requests..."

    # First request
    puts "\n📤 Request 1 (should create cache entry):"
    start_time = Time.current
    response1 = client.chat([{role: "user", content: test_message}])
    duration1 = Time.current - start_time

    puts "⏱️  Duration: #{(duration1 * 1000).round(0)}ms"
    puts "💬 Response: #{response1[:content]}"

    sleep 1 # Small delay

    # Second identical request (should hit cache)
    puts "\n📤 Request 2 (should hit cache, faster response):"
    start_time = Time.current
    response2 = client.chat([{role: "user", content: test_message}])
    duration2 = Time.current - start_time

    puts "⏱️  Duration: #{(duration2 * 1000).round(0)}ms"
    puts "💬 Response: #{response2[:content]}"

    if duration2 < duration1
      puts "\n✅ Cache likely working! Second request was #{((duration1 - duration2) * 1000).round(0)}ms faster"
    else
      puts "\n⚠️  No obvious cache benefit detected. Check Helicone dashboard for details."
    end

    puts "\n📊 View detailed analytics at: https://app.helicone.ai/dashboard"
  end

  desc "Test 1M token context window beta access with new headers"
  task test_1m_context: :environment do
    client = Ai::AnthropicClient.instance

    puts "🧪 Testing 1M token context window beta access..."
    puts "📋 Creating large context to test extended window..."

    # Create a large context to test 1M token window
    # Each paragraph is roughly 100-150 tokens
    large_context = []
    base_paragraph = "This is a test paragraph for the 1M context window beta feature. " * 20

    # Add system message
    large_context << {
      role: "system",
      content: "You are a helpful assistant testing the 1M context window feature."
    }

    # Add many context messages to approach large token counts
    200.times do |i|
      large_context << {
        role: "user",
        content: "Context block #{i + 1}: #{base_paragraph} Additional context about topic #{i + 1}."
      }
      large_context << {
        role: "assistant",
        content: "I understand context block #{i + 1}. This information has been processed and stored."
      }
    end

    # Add final question
    large_context << {
      role: "user",
      content: "Based on all the context above, please summarize what you've learned and confirm you can access all the information."
    }

    # Estimate token count (rough approximation: 1 token ≈ 3.5 chars)
    total_chars = large_context.sum { |msg| msg[:content].length }
    estimated_tokens = (total_chars / 3.5).round

    puts "📊 Estimated context size: ~#{estimated_tokens} tokens (#{total_chars} characters)"

    if estimated_tokens < 150_000
      puts "⚠️  Context size is #{estimated_tokens} tokens - below 200K threshold"
      puts "💡 The 1M context window is only available for prompts >200K tokens"
      puts "🔄 Generating larger context..."

      # Add more content to reach >200K tokens
      additional_needed = ((200_000 - estimated_tokens) / 100).ceil
      additional_needed.times do |i|
        large_context.insert(-2, {
          role: "user",
          content: "Additional large context #{i}: #{base_paragraph * 3} Extended information block with detailed content about various topics including technology, science, literature, and general knowledge."
        })
      end

      # Recalculate
      total_chars = large_context.sum { |msg| msg[:content].length }
      estimated_tokens = (total_chars / 3.5).round
      puts "📊 Updated context size: ~#{estimated_tokens} tokens (#{total_chars} characters)"
    end

    puts "\n🚀 Testing API call with large context..."

    begin
      start_time = Time.current

      response = client.chat(
        large_context,
        model: :claude_sonnet_4,
        temperature: 0.1,
        max_tokens: 1000,  # Small response to focus on context processing
        use_cache: false   # Disable cache to ensure fresh request
      )

      duration = Time.current - start_time

      if response[:success]
        puts "✅ SUCCESS! 1M context window appears to be available!"
        puts "⏱️  Response time: #{duration.round(2)}s"
        puts "📝 Response preview: #{response[:content][0..200]}..."

        if response[:usage]
          input_tokens = response[:usage]["input_tokens"] || 0
          output_tokens = response[:usage]["output_tokens"] || 0

          puts "\n📈 Token Usage:"
          puts "   Input tokens: #{input_tokens.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
          puts "   Output tokens: #{output_tokens}"
          puts "   Context window used: #{((input_tokens.to_f / 1_000_000) * 100).round(2)}% of 1M"

          if input_tokens > 200_000
            puts "🎉 CONFIRMED: Successfully processed >200K tokens!"
            puts "✨ Your API key has access to the 1M context window beta!"
          else
            puts "ℹ️  Input was #{input_tokens} tokens - below 200K threshold for 1M window"
          end
        end

      else
        puts "❌ Request failed: #{response[:error]}"

        if response[:error]&.include?("context") || response[:error]&.include?("token")
          puts "💡 This might indicate context window limitations"
        end
      end
    rescue => e
      puts "❌ Error during test: #{e.message}"

      if e.message.include?("context") || e.message.include?("token")
        puts "💡 Error suggests context window limitations"
        puts "📞 You may need to request beta access from Anthropic"
      end
    end

    puts "\n" + "=" * 60
    puts "1M Context Window Beta Information:"
    puts "• Beta feature for enterprise customers and high-usage accounts"
    puts "• Only activated for prompts >200K tokens"
    puts "• Different rate limits: 500K input + 100K output tokens/min"
    puts "• Contact Anthropic support to request beta access if needed"
    puts "• Documentation: https://docs.anthropic.com/en/docs/build-with-claude/context-windows"
    puts "=" * 60
  end
end
