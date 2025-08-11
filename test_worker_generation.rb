#\!/usr/bin/env ruby
require_relative 'config/environment'

app = App.find(151)
service = Deployment::FastPreviewService.new(app)

# Get the worker script
worker_script = service.send(:generate_fast_preview_worker)

# Write to file for inspection
File.write('generated_worker.js', worker_script)

puts "Worker script generated and saved to generated_worker.js"
puts "First 500 chars:"
puts worker_script[0..500]
puts "\n..."
puts "\nSearching for getFile function:"
if match = worker_script.match(/function getFile.*?\n.*?\n.*?\n/m)
  puts match[0]
end
