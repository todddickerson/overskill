#!/usr/bin/env ruby
require_relative 'config/environment'

puts "🔍 Debug AI Routing Logic"
puts "=" * 40

# Create client and inspect internal state
client = Ai::OpenRouterClient.new

puts "Client State:"
puts "  @gpt5_client: #{client.instance_variable_get(:@gpt5_client) ? 'Present' : 'Nil'}"
puts "  @anthropic_client: #{client.instance_variable_get(:@anthropic_client) ? 'Present' : 'Nil'}"

# Test the routing conditions
puts "\nRouting Tests:"

model = :gpt5
gpt5_client = client.instance_variable_get(:@gpt5_client)
anthropic_client = client.instance_variable_get(:@anthropic_client)

puts "  model == :gpt5: #{model == :gpt5}"
puts "  model.to_s.include?('gpt'): #{model.to_s.include?('gpt')}"
puts "  @gpt5_client present: #{!!gpt5_client}"
puts "  GPT-5 condition: #{gpt5_client && (model == :gpt5 || model.to_s.include?('gpt'))}"

puts "  use_anthropic default: true"
puts "  model.to_s.include?('claude'): #{model.to_s.include?('claude')}"
puts "  @anthropic_client present: #{!!anthropic_client}"

# Test with explicit logging
puts "\nDirect GPT-5 Test:"
begin
  # Call GPT-5 directly
  gpt5_response = gpt5_client.chat([
    { role: "user", content: "Say 'Direct GPT-5 working'" }
  ], model: 'gpt-5')
  
  puts "  Direct GPT-5 call: #{gpt5_response[:success] ? 'SUCCESS' : 'FAILED'}"
  if gpt5_response[:success]
    puts "  Content: #{gpt5_response[:content]}"
  else
    puts "  Error: #{gpt5_response[:error]}"
  end
rescue => e
  puts "  Exception: #{e.message}"
  puts "  This explains the fallback to Claude"
end

puts "\n" + "=" * 40