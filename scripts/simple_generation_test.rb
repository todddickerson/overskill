#!/usr/bin/env ruby
# Simple AI Generation Test

require_relative '../config/environment'

puts "🧪 Simple AI Generation Test"
puts "=" * 40

# Get existing app or create new one
app = App.find_by(id: 57) || App.first || App.create!(
  name: "Simple Test App",
  app_type: "saas",
  framework: "react",
  prompt: "Test app",
  team: Team.first,
  creator: Membership.first
)

puts "Using app: #{app.name} (ID: #{app.id})"

# Create a simple user message
message = app.app_chat_messages.create!(
  role: "user",
  content: "Create a simple counter app with increment and decrement buttons using React"
)

puts "Created message ID: #{message.id}"

# Process the message using the job
puts "\nProcessing with job..."
begin
  job = ProcessAppUpdateJob.new
  job.perform(message.id)
  
  # Check results
  message.reload
  puts "Message status: #{message.status || 'completed'}"
  
  # Check generated files
  files = app.app_files.reload
  puts "\nGenerated #{files.count} files:"
  files.each do |file|
    puts "  - #{file.path} (#{file.file_type}, #{file.size_bytes} bytes)"
  end
  
  # Check if main files exist
  has_index = files.any? { |f| f.path == "index.html" }
  has_js = files.any? { |f| f.path.end_with?(".js") }
  
  puts "\n✅ Results:"
  puts "  index.html: #{has_index ? 'YES' : 'NO'}"
  puts "  JavaScript: #{has_js ? 'YES' : 'NO'}"
  
rescue => e
  puts "❌ Error: #{e.message}"
  puts e.backtrace.first(5)
end