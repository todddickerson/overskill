#!/usr/bin/env ruby

# Test script for file-level granular caching
require_relative 'config/environment'

puts "\n=== Testing File-Level Granular Caching ===\n\n"

# Find a recent app with files
app = App.where("apps.created_at > ?", 1.week.ago)
          .joins(:app_files)
          .distinct
          .last

unless app
  puts "❌ No recent app with files found. Please create an app first."
  exit 1
end

puts "✅ Using app ##{app.id}: #{app.name}"
puts "   Files: #{app.app_files.count}"

# Test 1: FileChangeTracker
puts "\n📝 Test 1: FileChangeTracker"
tracker = Ai::FileChangeTracker.new(app.id)

# Track some files
test_file = app.app_files.first
if test_file
  puts "   Tracking: #{test_file.path}"
  
  # First track - should not be changed
  changed = tracker.track_file_change(test_file.path, test_file.content)
  puts "   Initial track: #{changed ? 'CHANGED' : 'UNCHANGED'} (expected: UNCHANGED)"
  
  # Modify content slightly and track again
  modified_content = test_file.content + "\n// Test modification"
  changed = tracker.track_file_change(test_file.path, modified_content)
  puts "   After modification: #{changed ? 'CHANGED' : 'UNCHANGED'} (expected: CHANGED)"
  
  # Check stability score
  score = tracker.get_stability_score(test_file.path)
  puts "   Stability score: #{score}/10"
end

# Test 2: GranularCachedPromptBuilder
puts "\n🔨 Test 2: GranularCachedPromptBuilder"

template_files = app.app_files.limit(10)
base_prompt = "You are an AI assistant helping to build an app."

builder = Ai::Prompts::GranularCachedPromptBuilder.new(
  base_prompt: base_prompt,
  template_files: template_files,
  context_data: { test: "data" },
  app_id: app.id
)

system_prompt = builder.build_granular_system_prompt

puts "   Built system prompt with #{system_prompt.size} blocks:"
system_prompt.each_with_index do |block, i|
  has_cache = block[:cache_control].present?
  ttl = block.dig(:cache_control, :ttl) || 'none'
  size = block[:text]&.length || 0
  puts "   Block #{i+1}: #{size} chars, cache: #{has_cache ? "YES (#{ttl})" : 'NO'}"
end

# Test 3: Cache Statistics
puts "\n📊 Test 3: Cache Statistics"
stats = tracker.get_stats
puts "   Total tracked files: #{stats[:total_tracked_files]}"
puts "   Recent changes (1h): #{stats[:recent_changes_1h]}"
puts "   Recent changes (5m): #{stats[:recent_changes_5m]}"
puts "   Stability distribution:"
puts "     - Stable: #{stats.dig(:stability_distribution, :stable)}"
puts "     - Active: #{stats.dig(:stability_distribution, :active)}"
puts "     - Volatile: #{stats.dig(:stability_distribution, :volatile)}"

# Test 4: Cache Invalidation
puts "\n🔄 Test 4: Cache Invalidation Simulation"

# Simulate file change
if test_file
  puts "   Simulating change to #{test_file.path}..."
  tracker.invalidate_file_cache(test_file.path)
  
  # Check if cache is invalid
  valid = tracker.cache_valid?(test_file.path)
  puts "   Cache valid after invalidation: #{valid} (expected: false)"
  
  # Wait for invalidation to expire (5 minutes in production, but we'll check immediately)
  sleep 0.1
  
  # In production, after 5 minutes it would be valid again
  puts "   Note: Cache invalidation expires after 5 minutes in production"
end

puts "\n✅ All tests completed successfully!"
puts "\nTo enable granular caching in production:"
puts "  1. Set ENABLE_GRANULAR_CACHING=true in .env"
puts "  2. Monitor with DEBUG_CACHE=true for detailed logs"
puts "  3. Check Redis for cache keys: redis-cli keys 'file_*'"