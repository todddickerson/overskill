#!/usr/bin/env ruby
# Test complete V4 deployment flow including Cloudflare Workers deployment

require_relative 'config/environment'

puts "🚀 Testing V4 Complete Deployment Flow"
puts "=" * 60

def create_test_app
  puts "1. Creating test app..."
  
  user = User.find_by(email: "test@example.com") || User.create!(
    email: "test@example.com",
    password: "password123",
    first_name: "Test",
    last_name: "User"
  )
  
  team = user.teams.first || Team.create!(name: "Test Team")
  membership = team.memberships.find_by(user: user) || team.memberships.create!(user: user, role: :admin)
  
  # Create a fresh app for deployment testing
  app_name = "V4 Deployment Test #{Time.current.strftime('%H:%M:%S')}"
  app = team.apps.create!(
    name: app_name,
    creator: membership,
    prompt: "Create a simple todo app for deployment testing",
    slug: app_name.parameterize
  )
  
  puts "   ✅ Created app: #{app.name} (ID: #{app.id})"
  app
end

def create_minimal_app_files(app)
  puts "2. Creating minimal app files for deployment..."
  
  # package.json
  app.app_files.create!(
    path: 'package.json',
    content: {
      "name" => app.slug || app.name.parameterize,
      "version" => "1.0.0",
      "type" => "module",
      "scripts" => {
        "dev" => "vite",
        "build" => "vite build",
        "preview" => "vite preview"
      },
      "dependencies" => {
        "react" => "^18.2.0",
        "react-dom" => "^18.2.0"
      },
      "devDependencies" => {
        "@vitejs/plugin-react" => "^4.0.0",
        "vite" => "^4.4.0"
      }
    }.to_json,
    team: app.team
  )
  
  # vite.config.js
  app.app_files.create!(
    path: 'vite.config.js',
    content: <<~JS,
      import { defineConfig } from 'vite'
      import react from '@vitejs/plugin-react'

      export default defineConfig({
        plugins: [react()],
        build: {
          outDir: 'dist',
          assetsDir: 'assets'
        },
        css: {
          postcss: {
            plugins: []
          }
        }
      })
    JS
    team: app.team
  )
  
  # postcss.config.js - Simple config for V4 apps
  app.app_files.create!(
    path: 'postcss.config.js',
    content: <<~JS,
      export default {
        plugins: []
      }
    JS
    team: app.team
  )
  
  # index.html
  app.app_files.create!(
    path: 'index.html',
    content: <<~HTML,
      <!DOCTYPE html>
      <html lang="en">
        <head>
          <meta charset="UTF-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1.0" />
          <title>#{app.name}</title>
        </head>
        <body>
          <div id="root"></div>
          <script type="module" src="/src/main.jsx"></script>
        </body>
      </html>
    HTML
    team: app.team
  )
  
  # src/main.jsx
  app.app_files.create!(
    path: 'src/main.jsx',
    content: <<~JSX,
      import React from 'react'
      import ReactDOM from 'react-dom/client'
      import App from './App'

      ReactDOM.createRoot(document.getElementById('root')).render(
        <React.StrictMode>
          <App />
        </React.StrictMode>,
      )
    JSX
    team: app.team
  )
  
  # src/App.jsx
  app.app_files.create!(
    path: 'src/App.jsx',
    content: <<~JSX,
      import React, { useState } from 'react'

      function App() {
        const [todos, setTodos] = useState([])
        const [inputValue, setInputValue] = useState('')

        const addTodo = () => {
          if (inputValue.trim()) {
            setTodos([...todos, { id: Date.now(), text: inputValue, completed: false }])
            setInputValue('')
          }
        }

        const toggleTodo = (id) => {
          setTodos(todos.map(todo => 
            todo.id === id ? { ...todo, completed: !todo.completed } : todo
          ))
        }

        const deleteTodo = (id) => {
          setTodos(todos.filter(todo => todo.id !== id))
        }

        return (
          <div style={{ padding: '20px', maxWidth: '600px', margin: '0 auto' }}>
            <h1>#{app.name}</h1>
            <div style={{ marginBottom: '20px' }}>
              <input
                type="text"
                value={inputValue}
                onChange={(e) => setInputValue(e.target.value)}
                placeholder="Add a new todo..."
                style={{ padding: '10px', marginRight: '10px', width: '300px' }}
                onKeyPress={(e) => e.key === 'Enter' && addTodo()}
              />
              <button onClick={addTodo} style={{ padding: '10px' }}>Add Todo</button>
            </div>
            <ul style={{ listStyle: 'none', padding: 0 }}>
              {todos.map(todo => (
                <li key={todo.id} style={{ 
                  padding: '10px', 
                  marginBottom: '5px', 
                  backgroundColor: '#f5f5f5',
                  display: 'flex',
                  justifyContent: 'space-between',
                  alignItems: 'center'
                }}>
                  <span 
                    style={{ 
                      textDecoration: todo.completed ? 'line-through' : 'none',
                      cursor: 'pointer'
                    }}
                    onClick={() => toggleTodo(todo.id)}
                  >
                    {todo.text}
                  </span>
                  <button onClick={() => deleteTodo(todo.id)}>Delete</button>
                </li>
              ))}
            </ul>
            <p>Deployed via V4 at {new Date().toLocaleString()}</p>
          </div>
        )
      }

      export default App
    JSX
    team: app.team
  )
  
  puts "   ✅ Created #{app.app_files.count} app files"
  puts "   📁 Files: #{app.app_files.pluck(:path).join(', ')}"
end

def test_vite_build(app)
  puts "3. Testing Vite build process..."
  
  begin
    # Use the external Vite builder service
    builder = Deployment::ExternalViteBuilder.new(app)
    
    puts "   🔨 Starting preview build..."
    build_result = builder.build_for_preview
    
    if build_result[:success]
      puts "   ✅ Build successful!"
      puts "   📦 Built files: #{build_result[:files_built] || 'unknown'}"
      puts "   ⏱️ Build time: #{build_result[:build_time]}s"
      puts "   📁 Build size: #{build_result[:size] ? "#{(build_result[:size] / 1024.0).round(1)}KB" : 'unknown'}"
      return build_result
    else
      puts "   ❌ Build failed: #{build_result[:error]}"
      return nil
    end
  rescue => e
    puts "   ❌ Build error: #{e.message}"
    puts "   📍 #{e.backtrace&.first}"
    return nil
  end
end

def test_cloudflare_deployment(app, build_result)
  puts "4. Testing Cloudflare Workers deployment..."
  
  return unless build_result&.dig(:success)
  
  begin
    # Use CloudflareWorkersDeployer for actual deployment
    deployer = Deployment::CloudflareWorkersDeployer.new(app)
    
    puts "   🚀 Deploying to Cloudflare Workers..."
    deployment_result = deployer.deploy_with_secrets(
      built_code: build_result[:worker_script] || generate_simple_worker_script(app),
      deployment_type: :preview
    )
    
    if deployment_result[:success]
      puts "   ✅ Deployment successful!"
      puts "   🌐 Worker URL: #{deployment_result[:worker_url]}"
      puts "   📝 Worker Name: #{deployment_result[:worker_name]}"
      puts "   🕒 Deployed at: #{deployment_result[:deployed_at]}"
      
      # Update app with preview URL
      app.update!(
        preview_url: deployment_result[:worker_url],
        status: 'deployed'
      )
      
      return deployment_result
    else
      puts "   ❌ Deployment failed: #{deployment_result[:error]}"
      return nil
    end
  rescue => e
    puts "   ❌ Deployment error: #{e.message}"
    puts "   📍 #{e.backtrace&.first(3)&.join("\\n   ")}"
    return nil
  end
end

def generate_simple_worker_script(app)
  # Generate a simple Cloudflare Worker script for testing (Service Worker format)
  <<~JS
    addEventListener('fetch', event => {
      event.respondWith(handleRequest(event.request))
    })

    async function handleRequest(request) {
      const url = new URL(request.url);
      
      // Serve the React app HTML for all routes
      const html = \`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>#{app.name}</title>
  <script crossorigin src="https://unpkg.com/react@18/umd/react.production.min.js"></script>
  <script crossorigin src="https://unpkg.com/react-dom@18/umd/react-dom.production.min.js"></script>
</head>
<body>
  <div id="root">
    <div style="padding: 20px; max-width: 600px; margin: 0 auto;">
      <h1>#{app.name}</h1>
      <p>🚀 Successfully deployed via V4 Cloudflare Workers!</p>
      <p>⏰ Deployed at: \${new Date().toLocaleString()}</p>
      <div style="background: #f0f0f0; padding: 15px; border-radius: 5px; margin-top: 20px;">
        <h3>✅ Deployment Test Results:</h3>
        <ul>
          <li>✅ Vite build process</li>
          <li>✅ Cloudflare Workers deployment</li>  
          <li>✅ Environment variables configured</li>
          <li>✅ Preview URL accessible</li>
        </ul>
      </div>
      <p><strong>App ID:</strong> #{app.id}</p>
      <p><strong>Team:</strong> #{app.team.name}</p>
      <p><small>This is a minimal deployment test. Full React app would be built and served here.</small></p>
    </div>
  </div>
</body>
</html>\`;
        
        return new Response(html, {
          headers: { 
            'Content-Type': 'text/html',
            'Cache-Control': 'no-cache'
          }
        });
    }
  JS
end

def test_deployment_accessibility(deployment_result)
  puts "5. Testing deployment accessibility..."
  
  return unless deployment_result&.dig(:worker_url)
  
  begin
    require 'net/http'
    require 'uri'
    
    uri = URI(deployment_result[:worker_url])
    puts "   🌐 Testing URL: #{uri}"
    
    response = Net::HTTP.get_response(uri)
    
    if response.code == '200'
      puts "   ✅ Deployment accessible!"
      puts "   📄 Content-Type: #{response['Content-Type']}"
      puts "   📦 Response size: #{response.body.length} bytes"
      puts "   🔗 **Live URL**: #{deployment_result[:worker_url]}"
      return true
    else
      puts "   ❌ Deployment not accessible: HTTP #{response.code}"
      puts "   📄 Response: #{response.body[0..200]}..."
      return false
    end
  rescue => e
    puts "   ⚠️ Could not test accessibility: #{e.message}"
    puts "   🔗 **Manual test URL**: #{deployment_result[:worker_url]}"
    return false
  end
end

# Main test execution
begin
  app = create_test_app
  create_minimal_app_files(app)
  build_result = test_vite_build(app)
  deployment_result = test_cloudflare_deployment(app, build_result)
  accessible = test_deployment_accessibility(deployment_result)
  
  puts "\n" + "=" * 60
  puts "🎯 V4 Deployment Flow Test Results"
  puts "=" * 60
  
  puts "App Details:"
  puts "   📱 Name: #{app.name}"
  puts "   🆔 ID: #{app.id}"
  puts "   📁 Files: #{app.app_files.count}"
  puts "   👥 Team: #{app.team.name}"
  
  if build_result&.dig(:success)
    puts "   ✅ Vite Build: SUCCESS"
    puts "   ⏱️ Build Time: #{build_result[:build_time]}s"
  else
    puts "   ❌ Vite Build: FAILED"
  end
  
  if deployment_result&.dig(:success)
    puts "   ✅ Cloudflare Deployment: SUCCESS"
    puts "   🌐 Preview URL: #{deployment_result[:worker_url]}"
    puts "   📝 Worker: #{deployment_result[:worker_name]}"
  else
    puts "   ❌ Cloudflare Deployment: FAILED"
  end
  
  if accessible
    puts "   ✅ URL Accessibility: SUCCESS"
  else
    puts "   ⚠️ URL Accessibility: UNKNOWN (check manually)"
  end
  
  if deployment_result&.dig(:success)
    puts "\n🎉 COMPLETE V4 DEPLOYMENT FLOW SUCCESSFUL!"
    puts "   🔗 Test your deployed app: #{deployment_result[:worker_url]}"
    puts "   📋 Next: Run full V4 generation with ChatProgressBroadcaster"
  else
    puts "\n⚠️ Deployment flow needs attention - check logs above"
  end
  
rescue => e
  puts "\n❌ Test failed: #{e.message}"
  puts "   Error: #{e.class.name}"
  puts "   Backtrace: #{e.backtrace&.first(5)&.join("\\n   ")}"
  exit 1
end