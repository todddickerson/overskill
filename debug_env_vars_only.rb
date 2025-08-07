#!/usr/bin/env ruby
require_relative 'config/environment'

puts "\n🔧 Environment Variables Debug"
puts "="*40

# Get test app
app = App.last
puts "📱 Test App: #{app.name} (#{app.id})"

# Create service
service = Deployment::FastPreviewService.new(app)
worker_name = "debug-env-test-#{app.id}"

# Debug method existence
puts "\n1️⃣ Checking method availability..."
puts "FastPreviewService responds to set_worker_env_vars: #{service.respond_to?(:set_worker_env_vars, true)}"
puts "FastPreviewService class: #{service.class}"
puts "FastPreviewService superclass: #{service.class.superclass}"

# Debug method signature
puts "\n2️⃣ Checking method signature..."
begin
  method_obj = service.method(:set_worker_env_vars)
  puts "Method object: #{method_obj}"
  puts "Method arity: #{method_obj.arity}"
  puts "Method source location: #{method_obj.source_location}"
rescue => e
  puts "Error getting method info: #{e.message}"
end

# Test calling with argument
puts "\n3️⃣ Testing method call with argument..."
begin
  service.send(:set_worker_env_vars, worker_name)
  puts "✅ Method call successful"
rescue => e
  puts "❌ Method call failed: #{e.message}"
  puts "   Backtrace:"
  e.backtrace.first(10).each_with_index do |line, i|
    puts "   #{i}: #{line}"
  end
end

puts "\n✅ Debug complete!"