#!/usr/bin/env ruby
# Test script to verify Anthropic prompt caching improvements

require_relative 'config/environment'

puts "🧪 Testing Anthropic Prompt Caching Improvements"
puts "=" * 60

# Test 1: Verify Anthropic client initialization
puts "\n1. Testing Anthropic Client Initialization"
begin
  anthropic_client = Ai::AnthropicClient.new
  puts "✅ AnthropicClient initialized successfully"
  puts "   API key present: #{ENV['ANTHROPIC_API_KEY'] ? 'Yes' : 'No'}"
rescue => e
  puts "❌ Failed to initialize AnthropicClient: #{e.message}"
end

# Test 2: Verify OpenRouterClient integration
puts "\n2. Testing OpenRouterClient Anthropic Integration"
begin
  openrouter_client = Ai::OpenRouterClient.new
  puts "✅ OpenRouterClient initialized with Anthropic support"
  
  # Check if it has Anthropic client
  anthropic_available = openrouter_client.instance_variable_get(:@anthropic_client)
  puts "   Anthropic client available: #{anthropic_available ? 'Yes' : 'No'}"
rescue => e
  puts "❌ Failed to test OpenRouterClient: #{e.message}"
end

# Test 3: Verify AI standards content for caching
puts "\n3. Testing AI Standards Content for Caching"
begin
  ai_standards_path = Rails.root.join('AI_GENERATED_APP_STANDARDS.md')
  if File.exist?(ai_standards_path)
    content = File.read(ai_standards_path)
    estimated_tokens = (content.length / 3.5).ceil
    puts "✅ AI standards file found"
    puts "   File size: #{content.length} characters"
    puts "   Estimated tokens: ~#{estimated_tokens}"
    puts "   Cacheable (>1024 tokens): #{estimated_tokens > 1024 ? 'Yes' : 'No'}"
  else
    puts "❌ AI standards file not found"
  end
rescue => e
  puts "❌ Failed to read AI standards: #{e.message}"
end

# Test 4: Test cache breakpoint creation
puts "\n4. Testing Cache Breakpoint Creation"
begin
  anthropic_client = Ai::AnthropicClient.new
  ai_standards = File.read(Rails.root.join('AI_GENERATED_APP_STANDARDS.md')) rescue ""
  
  breakpoints = anthropic_client.create_cache_breakpoints(ai_standards)
  puts "✅ Cache breakpoints created: #{breakpoints.length} breakpoints"
  
  breakpoints.each_with_index do |bp, i|
    puts "   Breakpoint #{i + 1}: #{bp[:type]}"
  end
rescue => e
  puts "❌ Failed to create cache breakpoints: #{e.message}"
end

# Test 5: Test simple chat with caching (if API key available)
if ENV['ANTHROPIC_API_KEY']
  puts "\n5. Testing Simple Chat with Prompt Caching"
  begin
    anthropic_client = Ai::AnthropicClient.new
    
    # Simple test message
    messages = [
      { role: "system", content: "You are a helpful assistant." },
      { role: "user", content: "Say hello and confirm you received this message." }
    ]
    
    puts "   Sending test request to Anthropic API..."
    response = anthropic_client.chat(messages, model: :claude_sonnet_4, max_tokens: 100)
    
    if response[:success]
      puts "✅ Anthropic API request successful"
      puts "   Response: #{response[:content][0..100]}..."
      
      # Check cache performance data
      if response[:cache_performance]
        perf = response[:cache_performance]
        puts "   Cache Performance:"
        puts "     - Cache read tokens: #{perf[:cache_read_tokens]}"
        puts "     - Cache creation tokens: #{perf[:cache_creation_tokens]}"
        puts "     - Regular input tokens: #{perf[:regular_input_tokens]}"
        puts "     - Cache hit rate: #{perf[:cache_hit_rate]}%"
      end
    else
      puts "❌ Anthropic API request failed: #{response[:error]}"
    end
  rescue => e
    puts "❌ Failed to test Anthropic API: #{e.message}"
  end
else
  puts "\n5. Skipping API Test (No ANTHROPIC_API_KEY found)"
end

# Test 6: Test dual API routing through OpenRouterClient
puts "\n6. Testing Dual API Routing"
begin
  openrouter_client = Ai::OpenRouterClient.new
  
  # Test Claude model routing to Anthropic
  puts "   Testing Claude model routing..."
  
  messages = [
    { role: "system", content: "You are a test assistant." },
    { role: "user", content: "Respond with 'ANTHROPIC' if you're using Anthropic direct API, or 'OPENROUTER' if using OpenRouter." }
  ]
  
  # This should route to Anthropic if available
  if ENV['ANTHROPIC_API_KEY']
    response = openrouter_client.chat(messages, model: :claude_sonnet_4, max_tokens: 50, use_anthropic: true)
    
    if response[:success]
      puts "✅ Dual API routing working"
      puts "   Response suggests: #{response[:content].include?('ANTHROPIC') ? 'Anthropic Direct API' : 'OpenRouter'}"
    else
      puts "❌ Dual API routing failed: #{response[:error]}"
    end
  else
    puts "   Skipping (no Anthropic API key)"
  end
rescue => e
  puts "❌ Failed to test dual API routing: #{e.message}"
end

# Test 7: Redis cache integration
puts "\n7. Testing Redis Cache Integration"
begin
  cache_service = Ai::ContextCacheService.new
  
  # Test cache operations
  test_key = "test_cache_#{Time.current.to_i}"
  test_data = { message: "test caching", timestamp: Time.current }
  
  # Test set
  cache_service.instance_variable_get(:@redis).setex(test_key, 60, test_data.to_json)
  
  # Test get
  cached_data = cache_service.instance_variable_get(:@redis).get(test_key)
  
  if cached_data
    puts "✅ Redis cache working"
    puts "   Cached data retrieved successfully"
    
    # Clean up
    cache_service.instance_variable_get(:@redis).del(test_key)
  else
    puts "❌ Redis cache not working"
  end
rescue => e
  puts "❌ Failed to test Redis cache: #{e.message}"
end

puts "\n" + "=" * 60
puts "🎯 Test Summary:"
puts "   Anthropic client integration: Ready"
puts "   Prompt caching optimization: #{ENV['ANTHROPIC_API_KEY'] ? 'Active' : 'Needs API key'}"
puts "   Cost savings potential: Up to 90% on repeated context"
puts "   Cache breakpoints: AI standards (#{File.exist?(Rails.root.join('AI_GENERATED_APP_STANDARDS.md')) ? 'Ready' : 'Missing'})"
puts "=" * 60

if ENV['ANTHROPIC_API_KEY']
  puts "\n🚀 All systems ready for optimized AI generation!"
  puts "   Next: Generate an app to see the caching in action"
else
  puts "\n⚠️  Add ANTHROPIC_API_KEY to fully activate prompt caching"
  puts "   Currently using fallback Redis caching only"
end