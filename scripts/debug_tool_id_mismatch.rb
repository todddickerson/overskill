#!/usr/bin/env ruby
# Debug script to understand tool_use_id mismatch issue

require_relative '../config/environment'

puts "🔍 Debugging Tool ID Mismatch Issue"
puts "=" * 60
puts

# Find the most recent message with tools
message = AppChatMessage.joins(:app)
  .where.not(conversation_flow: nil)
  .where("conversation_flow::text LIKE '%tools%'")
  .order(created_at: :desc)
  .first

if message.nil?
  puts "❌ No messages with tools found"
  exit 1
end

puts "Message ID: #{message.id}"
puts "App: #{message.app.name} (ID: #{message.app.id})"
puts

# Analyze conversation_flow
flow = message.conversation_flow
tools_entries = flow.select { |item| item['type'] == 'tools' }

puts "Found #{tools_entries.count} tools entries in conversation_flow"
puts

tools_entries.each_with_index do |entry, entry_index|
  puts "Tools Entry ##{entry_index + 1}:"
  puts "  Execution ID: #{entry['execution_id']}"
  puts "  Status: #{entry['status']}"
  puts "  Tools count: #{entry['tools']&.count || 0}"
  
  if entry['tools'].present?
    entry['tools'].each_with_index do |tool, tool_index|
      next if tool.nil?
      
      puts "    Tool ##{tool_index}:"
      puts "      ID: #{tool['id'] || 'MISSING!'}"
      puts "      Name: #{tool['name']}"
      puts "      Status: #{tool['status']}"
      puts "      File Path: #{tool['file_path']}" if tool['file_path']
      
      # Check if tool has all required fields for tool_result
      if tool['id'].nil?
        puts "      ⚠️ WARNING: Tool missing 'id' field - will cause tool_result mismatch!"
      end
    end
  end
  puts
end

puts "=" * 60
puts "Checking last conversation messages in database..."
puts

# Try to reconstruct what would happen in IncrementalToolCompletionJob
if tools_entries.any?
  last_tools_entry = tools_entries.last
  
  puts "Simulating IncrementalToolCompletionJob.format_tool_results:"
  puts
  
  if last_tools_entry['tools'].present?
    last_tools_entry['tools'].each_with_index do |tool, index|
      next if tool.nil?
      
      tool_use_id = tool['id'] || "tool_#{index}"
      puts "Tool #{index}: would generate tool_use_id = '#{tool_use_id}'"
      
      if tool['id'].nil?
        puts "  ⚠️ Using fallback ID because tool['id'] is nil"
      end
    end
  end
end

puts
puts "=" * 60
puts "Recent execution IDs in Redis cache:"
puts

# Check Redis for recent execution states
# Use Rails.cache.redis.then to properly access Redis through connection pool
begin
  Rails.cache.redis.then do |redis|
    pattern = "incremental_tool:*:state"
    redis_keys = redis.keys(pattern)
    
    if redis_keys.any?
      redis_keys.last(5).each do |key|
        execution_id = key.split(':')[1]
        state = Rails.cache.read("incremental_tool:#{execution_id}:state")
        
        if state
          puts "Execution #{execution_id}:"
          puts "  Status: #{state['status']}"
          puts "  Dispatched: #{state['dispatched_count']}"
          puts "  Completed: #{state['completed_count']}"
          puts "  Started: #{Time.at(state['started_at']).strftime('%Y-%m-%d %H:%M:%S')}" if state['started_at']
        end
      end
    else
      puts "(No execution states found in Redis)"
    end
  end
rescue => e
  puts "Could not check Redis: #{e.message}"
end

puts
puts "💡 Common causes of tool_use_id mismatch:"
puts "1. Tool IDs not preserved when storing in conversation_flow"
puts "2. Tools array has nil entries causing index mismatch"
puts "3. Assistant message tool_use blocks don't match stored tools"
puts "4. Race condition between storing tools and building messages"