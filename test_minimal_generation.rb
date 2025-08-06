#!/usr/bin/env ruby
require_relative 'config/environment'

# Test with minimal generation for deployment
puts "\n=== Testing Minimal Generation for Deployment ==="

# Create minimal files directly (bypass AI for testing)
files = [
  {
    'path' => 'index.html',
    'content' => <<~HTML
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Counter App</title>
        <script src="https://cdn.tailwindcss.com"></script>
      </head>
      <body class="bg-gray-100 flex items-center justify-center min-h-screen">
        <div id="root"></div>
        <script src="/src/App.js"></script>
      </body>
      </html>
    HTML
  },
  {
    'path' => 'src/App.js',
    'content' => <<~JS
      // Simple counter app
      let count = 0;
      
      function updateUI() {
        document.getElementById('root').innerHTML = `
          <div class="bg-white p-8 rounded-lg shadow-lg">
            <h1 class="text-3xl font-bold mb-4">Counter: ${count}</h1>
            <div class="space-x-4">
              <button onclick="increment()" class="bg-blue-500 text-white px-4 py-2 rounded">+</button>
              <button onclick="decrement()" class="bg-red-500 text-white px-4 py-2 rounded">-</button>
            </div>
          </div>
        `;
      }
      
      window.increment = () => { count++; updateUI(); };
      window.decrement = () => { count--; updateUI(); };
      
      // Initialize
      updateUI();
    JS
  },
  {
    'path' => 'wrangler.toml',
    'content' => <<~TOML
      name = "counter-app"
      main = "worker.js"
      compatibility_date = "2024-01-01"
      
      [env.production]
      vars = { ENVIRONMENT = "production" }
    TOML
  }
]

# Create app and save files
team = Team.first || Team.create!(name: "Test Team")
membership = team.memberships.first

app = App.create!(
  team: team,
  creator: membership,
  name: "Counter Test #{Time.now.to_i}",
  slug: "counter-test-#{Time.now.to_i}",
  prompt: "Counter app",
  app_type: "saas",
  framework: "vanilla",
  status: "generated",
  base_price: 0
)

# Save files
files.each do |file_data|
  app.app_files.create!(
    team: team,
    path: file_data['path'],
    content: file_data['content'],
    file_type: File.extname(file_data['path']).delete('.').presence || 'html'
  )
end

puts "Created app: #{app.name} (#{app.id})"
puts "Files: #{app.app_files.count}"

# Deploy it
puts "\n🚀 Deploying to Cloudflare..."
service = Deployment::CloudflarePreviewService.new(app)
result = service.update_preview!

if result[:success]
  puts "✅ Deployment successful!"
  puts "Preview URL: #{result[:preview_url]}"
  puts "\nYou can visit: #{result[:preview_url]}"
  
  # Update app status
  app.update!(status: 'published')
else
  puts "❌ Deployment failed: #{result[:error]}"
end

puts "\n=== Test Complete ===="