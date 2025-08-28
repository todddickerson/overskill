#!/usr/bin/env ruby
# Test script to verify text appears before tools and updates properly

message = AppChatMessage.last
if message.nil?
  puts "❌ No app chat messages found"
  exit 1
end

puts "\n📋 Testing message ##{message.id} conversation_flow ordering..."
puts "=" * 60

flow = message.conversation_flow || []
puts "Total flow items: #{flow.count}"
puts

# Check order of items
text_index = nil
tools_index = nil

flow.each_with_index do |item, index|
  type = item['type']
  
  if type == 'message' || type == 'content'
    if text_index.nil?
      text_index = index
      content = item['content']
      
      if content.is_a?(String)
        puts "✅ Text entry found at index #{index}"
        puts "   Content length: #{content.length} chars"
        
        if content.empty?
          puts "   ⚠️  Content is empty (might be placeholder)"
        elsif content == "I'll create"
          puts "   ⚠️  Content appears stuck at initial value"
        elsif content.length > 20
          puts "   ✅ Content appears to be complete"
          puts "   Preview: #{content.truncate(100)}"
        end
      else
        puts "❌ Text entry at index #{index} has wrong type: #{content.class}"
      end
    end
  elsif type == 'tools'
    if tools_index.nil?
      tools_index = index
      tools = item['tools'] || item['calls'] || []
      puts "🔧 Tools entry found at index #{index}"
      puts "   Number of tools: #{tools.count}"
      puts "   First tool: #{tools.first['name']}" if tools.any?
    end
  end
end

puts
puts "=" * 60
puts "Order Analysis:"

if text_index && tools_index
  if text_index < tools_index
    puts "✅ CORRECT ORDER: Text (index #{text_index}) appears BEFORE tools (index #{tools_index})"
  else
    puts "❌ WRONG ORDER: Text (index #{text_index}) appears AFTER tools (index #{tools_index})"
  end
elsif text_index && tools_index.nil?
  puts "ℹ️  Only text found, no tools in this message"
elsif text_index.nil? && tools_index
  puts "⚠️  Only tools found, no text in this message"
else
  puts "⚠️  No text or tools found in conversation_flow"
end

puts
puts "Monitoring logs for streaming updates..."
puts "Run 'tail -f log/development.log | grep V5_INCREMENTAL' to see detailed logs"