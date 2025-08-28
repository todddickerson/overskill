#!/usr/bin/env ruby
# Test script to verify conversation_flow content fix

# Check the last message's conversation flow structure
message = AppChatMessage.last
if message.nil?
  puts "❌ No app chat messages found"
  exit 1
end

puts "\n📝 Checking message ##{message.id} conversation_flow structure..."
puts "=" * 60

flow = message.conversation_flow || []
puts "Total flow items: #{flow.count}"
puts

# Check for double-nested content issues
has_issues = false
flow.each_with_index do |item, index|
  next unless item['type'] == 'message' || item['type'] == 'content'
  
  content = item['content']
  
  # Check if content is a hash (indicates double-nesting issue)
  if content.is_a?(Hash)
    puts "❌ Item #{index}: Content is double-nested (hash instead of string)!"
    puts "   Type: #{item['type']}"
    puts "   Content structure: #{content.keys.inspect}"
    puts "   Actual content: #{content['content']&.truncate(50)}"
    has_issues = true
  elsif content.is_a?(String)
    puts "✅ Item #{index}: Content is correctly stored as string"
    puts "   Type: #{item['type']}"
    puts "   Content: #{content.truncate(100)}"
  else
    puts "⚠️  Item #{index}: Unexpected content type: #{content.class}"
  end
  puts
end

# Check if text is properly streaming and updating
text_items = flow.select { |item| item['type'] == 'message' || item['type'] == 'content' }
if text_items.any?
  last_text = text_items.last
  content = last_text['content']
  
  if content.is_a?(String)
    if content == "I'll create"
      puts "⚠️  Text content appears stuck at initial value: '#{content}'"
      puts "   This suggests streaming updates are not working properly"
    elsif content.length > 20
      puts "✅ Text content appears to have been updated via streaming"
      puts "   Length: #{content.length} characters"
    end
  end
end

puts
puts "=" * 60
if has_issues
  puts "❌ Issues found with conversation_flow structure"
  puts "   Run this after deploying the fix to verify it's resolved"
else
  puts "✅ conversation_flow structure looks correct!"
  puts "   Content is properly stored as strings, not nested hashes"
end