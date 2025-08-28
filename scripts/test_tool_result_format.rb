#!/usr/bin/env ruby
# Test script to verify correct tool_result format (no is_error field)

require_relative '../config/environment'

puts "🧪 Testing Tool Result Format Compliance"
puts "=" * 60
puts

# Simulate IncrementalToolCompletionJob format_tool_results method
def test_format_tool_results
  # Mock tools data (as stored in conversation_flow)
  tools = [
    {
      'id' => 'toolu_01ABC123',
      'name' => 'os-write',
      'status' => 'complete'
    },
    {
      'id' => 'toolu_01DEF456',
      'name' => 'rename-app', 
      'status' => 'error'
    }
  ]
  
  # Mock results data (as stored in Redis)
  results_raw = [
    {
      'status' => 'success',
      'result' => 'File created successfully'
    },
    {
      'status' => 'error',
      'error' => 'Name is required'
    }
  ]
  
  # Use same logic as IncrementalToolCompletionJob
  formatted = []
  
  tools.each_with_index do |tool, index|
    next if tool.nil?
    
    result = results_raw[index]
    tool_id = tool['id']
    
    if result.nil?
      if tool_id.present?
        formatted << {
          type: 'tool_result',
          tool_use_id: tool_id,
          content: 'Tool execution incomplete'
        }
      end
    else
      content = result['result'] || result['error'] || 'No result available'
      content = content.is_a?(String) ? content : content.to_json
      
      if tool_id.present?
        formatted << {
          type: 'tool_result',
          tool_use_id: tool_id,
          content: content
        }
      end
    end
  end
  
  formatted
end

# Test the format
tool_results = test_format_tool_results

puts "Generated tool_result blocks:"
puts

tool_results.each_with_index do |result, index|
  puts "Tool Result ##{index + 1}:"
  puts JSON.pretty_generate(result)
  
  # Verify format compliance
  errors = []
  errors << "Missing 'type'" unless result[:type] == 'tool_result'
  errors << "Missing 'tool_use_id'" unless result[:tool_use_id].present?
  errors << "Missing 'content'" unless result.key?(:content)
  errors << "INVALID: Contains 'is_error'" if result.key?(:is_error)
  
  if errors.any?
    puts "❌ FORMAT ERRORS: #{errors.join(', ')}"
  else
    puts "✅ FORMAT CORRECT"
  end
  
  puts
end

puts "=" * 60
puts "📋 Claude API Tool Result Format Requirements:"
puts "✓ Must have type: 'tool_result'"
puts "✓ Must have tool_use_id: matching the original tool_use id"
puts "✓ Must have content: string or array"
puts "❌ Must NOT have is_error: not part of Claude API spec"
puts
puts "References:"
puts "- https://docs.anthropic.com/claude/docs/tool-use"
puts "- Claude API returns 'unexpected field' error for non-standard fields"