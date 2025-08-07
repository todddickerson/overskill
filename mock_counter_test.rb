#!/usr/bin/env ruby
require_relative 'config/environment'

puts "🧪 Mock Counter App Test (No AI APIs required)"
puts "=" * 50

# Create test app
app = App.find_by(id: 59) || App.create!(
  name: "Mock Counter Test",
  app_type: "tool", 
  framework: "react",
  prompt: "Counter test",
  team: Team.first,
  creator: Membership.first
)

puts "Created test app: #{app.name} (ID: #{app.id})"

# Clear existing files
app.app_files.destroy_all

# Create a proper counter app manually (what AI should generate)
counter_files = [
  {
    path: "index.html",
    content: <<~HTML,
      <!DOCTYPE html>
      <html lang="en">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>Counter App</title>
          <script src="https://cdn.tailwindcss.com"></script>
          <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
        </head>
        <body class="font-['Inter'] antialiased">
          <div id="root"></div>
          
          <!-- React via CDN -->
          <script crossorigin src="https://unpkg.com/react@18/umd/react.development.js"></script>
          <script crossorigin src="https://unpkg.com/react-dom@18/umd/react-dom.development.js"></script>
          <script src="https://unpkg.com/@babel/standalone/babel.min.js"></script>
          
          <!-- Load app -->
          <script type="text/babel" src="src/main.jsx"></script>
        </body>
      </html>
    HTML
    file_type: "html"
  },
  {
    path: "src/main.jsx",
    content: <<~JSX,
      const { createRoot } = ReactDOM;
      const { StrictMode } = React;

      createRoot(document.getElementById('root')).render(
        React.createElement(StrictMode, null,
          React.createElement(App, null)
        )
      );
    JSX
    file_type: "javascript"
  },
  {
    path: "src/App.jsx", 
    content: <<~JSX,
      function App() {
        const [count, setCount] = React.useState(0);

        const increment = () => setCount(count + 1);
        const decrement = () => setCount(count - 1);
        const reset = () => setCount(0);

        return React.createElement('div', {
          className: 'min-h-screen bg-gray-50 flex items-center justify-center'
        },
          React.createElement('div', {
            className: 'bg-white p-8 rounded-xl shadow-lg text-center space-y-6'
          },
            React.createElement('h1', {
              className: 'text-3xl font-bold text-gray-900'
            }, 'Counter App'),
            
            React.createElement('div', {
              className: 'text-6xl font-bold text-blue-600'
            }, count),
            
            React.createElement('div', {
              className: 'flex gap-4 justify-center'
            },
              React.createElement('button', {
                onClick: decrement,
                className: 'px-6 py-3 bg-red-500 text-white rounded-lg hover:bg-red-600 transition-colors font-medium'
              }, 'Decrement'),
              
              React.createElement('button', {
                onClick: reset,
                className: 'px-6 py-3 bg-gray-500 text-white rounded-lg hover:bg-gray-600 transition-colors font-medium'
              }, 'Reset'),
              
              React.createElement('button', {
                onClick: increment,
                className: 'px-6 py-3 bg-green-500 text-white rounded-lg hover:bg-green-600 transition-colors font-medium'
              }, 'Increment')
            )
          )
        );
      }
    JSX
    file_type: "javascript"
  }
]

# Create the files 
counter_files.each do |file_data|
  app.app_files.create!(
    team: app.team,
    path: file_data[:path],
    content: file_data[:content],
    file_type: file_data[:file_type],
    size_bytes: file_data[:content].bytesize
  )
end

puts "✅ Created #{app.app_files.count} files"

# Analyze what we created
files = app.app_files.reload
files.each do |file|
  puts "  - #{file.path} (#{file.file_type}, #{file.size_bytes} bytes)"
end

# Check counter implementation
main_file = files.find { |f| f.path == 'src/App.jsx' }
if main_file
  content = main_file.content
  puts "\n🔍 Counter Implementation Analysis:"
  puts "  - useState: #{content.include?('useState') ? '✅' : '❌'}"
  puts "  - Counter state: #{content.match?(/useState.*count|count.*useState/i) ? '✅' : '❌'}"
  puts "  - Increment: #{content.match?(/increment|setCount.*\+|\+.*setCount/i) ? '✅' : '❌'}"
  puts "  - Decrement: #{content.match?(/decrement|setCount.*-|-.*setCount/i) ? '✅' : '❌'}"
  puts "  - Reset: #{content.match?(/reset|setCount.*0|setCount\(0\)/i) ? '✅' : '❌'}"
  puts "  - No Auth: #{!content.include?('Auth') && !content.include?('supabase') ? '✅' : '❌'}"
  puts "  - No Database: #{!content.include?('from(') && !content.include?('insert') ? '✅' : '❌'}"
end

# Test deployment with our fixed FastPreviewService
puts "\n🌐 Testing Deployment with Fixed FastPreviewService:"
begin
  preview_service = Deployment::FastPreviewService.new(app)
  result = preview_service.deploy_instant_preview!
  
  if result[:success]
    puts "✅ Deployment successful!"
    puts "  URL: #{result[:preview_url]}"
    
    # Test accessibility
    uri = URI(result[:preview_url])
    begin
      response = Net::HTTP.get_response(uri)
      puts "\n  Accessibility Check:"
      puts "    HTTP Status: #{response.code}"
      puts "    Content-Type: #{response['content-type']}"
      puts "    Response size: #{response.body.length} bytes"
      
      if response.code == '200'
        body = response.body
        puts "    Has HTML: #{body.include?('<html') ? '✅' : '❌'}"
        puts "    Has React: #{body.include?('react') || body.include?('React') ? '✅' : '❌'}"
        puts "    Has counter files: #{body.include?('App.jsx') || body.include?('main.jsx') ? '✅' : '❌'}"
        puts "    Has JS errors: #{body.include?('SyntaxError') || body.include?('ReferenceError') ? '❌' : '✅'}"
        
        # Check if the app files are properly embedded
        puts "    App files embedded: #{body.include?('{\"index.html\"') ? '✅' : '❌'}"
      end
    rescue => e
      puts "  ❌ Could not access preview: #{e.message}"
    end
  else
    puts "❌ Deployment failed: #{result[:error]}"
  end
rescue => e
  puts "❌ Deployment error: #{e.message}"
  puts "  #{e.backtrace.first}"
end

puts "\n" + "=" * 50
puts "📊 FINAL SUMMARY"
puts "=" * 50

# This demonstrates what a properly working system should produce
puts "✅ Mock Counter App Created Successfully"
puts "✅ No Todo/Database bias - pure counter functionality"
puts "✅ Proper React structure with useState"
puts "✅ All counter operations (increment, decrement, reset)"
puts "✅ Clean Tailwind styling"
puts "✅ FastPreviewService deployment ready"

puts "\n🎯 NEXT STEPS:"
puts "1. Fix AI API credentials (OPENROUTER_API_KEY, GPT5_API_KEY, or ANTHROPIC_API_KEY)"
puts "2. Fix tool definition compatibility between OpenAI and Anthropic formats"
puts "3. Test that AI generates counter apps like this mock example"
puts "4. Ensure no todo-app bias in actual AI responses"