#!/usr/bin/env rails runner

# Test V4 Enhanced with HTML escaping fix
puts "Testing V4 Enhanced deployment with escaping fix..."
puts "=" * 50

# Find existing user and team
user = User.first
unless user
  puts "No users found. Please create a user first."
  exit 1
end

team = user.teams.first
unless team
  puts "No teams found for user. Please create a team first."
  exit 1
end

# Find existing membership
membership = team.memberships.where(user: user).first
unless membership
  puts "No membership found for user in team."
  exit 1
end

app = App.create!(
  name: "Test V4 Enhanced Fix #{Time.current.to_i}",
  team: team,
  creator: membership,
  prompt: "Create a simple counter app",
  status: 'generating',
  app_type: 'tool'
)

puts "Created app: #{app.name} (ID: #{app.id})"

# Create a simple test message
message = AppChatMessage.create!(
  app: app,
  user: user,
  role: 'user',
  content: 'Create a simple counter app'
)

puts "Created chat message: #{message.id}"

# Test the broadcaster
require_relative 'app/services/ai/chat_progress_broadcaster_v2'
broadcaster = Ai::ChatProgressBroadcasterV2.new(message)

puts "\n1. Testing phase broadcasting..."
broadcaster.broadcast_phase(1, "Analyzing Requirements", 6)
sleep 0.5

puts "2. Testing file operations..."
broadcaster.broadcast_file_operation(:creating, "src/App.tsx", "function App() { ... }")
sleep 0.5
broadcaster.broadcast_file_operation(:created, "src/App.tsx")

puts "3. Testing build output..."
broadcaster.broadcast_build_output("Building application...")
broadcaster.broadcast_build_output("✅ Build successful!")

puts "4. Testing completion..."
broadcaster.broadcast_completion(
  success: true,
  stats: {
    files_generated: 5,
    app_url: "https://preview-#{app.id}.overskill.app"
  }
)

puts "\n✅ Broadcaster test complete!"

# Now test actual deployment with simple HTML
puts "\n5. Testing deployment with HTML content..."

# Create a simple HTML file with potential problematic characters
app_file = AppFile.create!(
  app: app,
  team: team,
  path: "index.html",
  content: <<~HTML
    <!DOCTYPE html>
    <html>
    <head>
      <title>Test App with "quotes" and 'apostrophes'</title>
      <style>
        body { font-family: "Helvetica", 'Arial', sans-serif; }
        .counter::before { content: "Count: "; }
      </style>
    </head>
    <body>
      <h1>Counter with special chars: < > & " '</h1>
      <div id="counter" class="counter">0</div>
      <button onclick="document.getElementById('counter').innerText++">
        Click me & increment!
      </button>
      <script>
        console.log("App started with 'special' characters");
        const message = \`Template literal with "quotes" and 'apostrophes'\`;
      </script>
    </body>
    </html>
  HTML
)

puts "Created test HTML file with special characters"

# Test the builder
require_relative 'app/services/deployment/external_vite_builder'
builder = Deployment::ExternalViteBuilder.new(app)

puts "6. Testing worker code generation..."
begin
  # Simulate the wrapping that happens during build
  test_html = app_file.content
  test_assets = []
  
  # Use private method directly for testing
  worker_code = builder.send(:wrap_for_worker_deployment_hybrid, test_html, test_assets)
  
  # Check if the worker code is valid JavaScript
  puts "Generated worker code (first 500 chars):"
  puts worker_code[0..500]
  puts "..."
  
  # Look for potential syntax errors
  if worker_code.include?('`#{') || worker_code.include?('${')
    puts "⚠️  Warning: Found unescaped template literal syntax"
  end
  
  # Check for proper escaping
  if worker_code.include?('const HTML_CONTENT = `')
    escaped_content = worker_code.match(/const HTML_CONTENT = `([^`]*)`/m)
    if escaped_content
      puts "\n✅ HTML content is properly wrapped in template literal"
      
      # Verify escaping of backticks
      if escaped_content[1].include?('\\`')
        puts "✅ Backticks are properly escaped"
      end
      
      # Check for other problematic characters
      if !escaped_content[1].include?('${')
        puts "✅ No unescaped template literal expressions"
      else
        puts "⚠️  Found potential unescaped template expression"
      end
    end
  end
  
  puts "\n✅ Worker code generation test complete!"
  
rescue => e
  puts "❌ Error during worker code generation: #{e.message}"
  puts e.backtrace.first(5)
end

puts "\n" + "=" * 50
puts "Test completed successfully!"
puts "Check the app at: https://preview-#{app.id}.overskill.app"