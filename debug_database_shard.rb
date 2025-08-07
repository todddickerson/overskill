#!/usr/bin/env ruby
require_relative 'config/environment'

puts "\n🔧 DatabaseShard Model Debug"
puts "="*40

# Test model loading
puts "\n1️⃣ Testing DatabaseShard model loading..."
begin
  DatabaseShard
  puts "✅ DatabaseShard model loaded successfully"
rescue => e
  puts "❌ DatabaseShard model loading failed: #{e.message}"
  puts "   Backtrace:"
  e.backtrace.first(10).each_with_index do |line, i|
    puts "   #{i}: #{line}"
  end
  exit 1
end

# Test enum access
puts "\n2️⃣ Testing enum access..."
begin
  puts "Available statuses: #{DatabaseShard.statuses.keys}"
  puts "✅ Enum access successful"
rescue => e
  puts "❌ Enum access failed: #{e.message}"
  e.backtrace.first(5).each_with_index do |line, i|
    puts "   #{i}: #{line}"
  end
end

# Test creating/accessing a shard
puts "\n3️⃣ Testing shard access..."
begin
  shard = DatabaseShard.first
  if shard
    puts "Found shard: #{shard.name}"
    puts "Status: #{shard.status}"
    puts "✅ Shard access successful"
  else
    puts "No shards found - this is fine for testing"
  end
rescue => e
  puts "❌ Shard access failed: #{e.message}"
  e.backtrace.first(5).each_with_index do |line, i|
    puts "   #{i}: #{line}"
  end
end

puts "\n✅ Debug complete!"