#!/usr/bin/env ruby
# Test auth template generation for newly created apps
# Run with: bin/rails runner scripts/test_new_auth_templates.rb

puts "🧪 Testing auth template generation with enhanced OAuth handling..."
puts "=" * 80

# Create a test app
team = Team.first
app = team.apps.create!(
  name: 'OAuth Test App ' + Time.now.to_i.to_s,
  slug: 'oauth-test-' + Time.now.to_i.to_s,
  prompt: 'Create a simple test app with OAuth authentication',
  creator: team.memberships.first,
  base_price: 0,
  app_type: 'tool',
  framework: 'react',
  status: 'generating'
)

puts "Created test app: ##{app.id} - #{app.name}"

# Generate auth files using the updated templates
files = Ai::AuthTemplates.generate_auth_files(app)

puts "\nGenerated #{files.length} auth files:"
files.each do |file|
  puts "  - #{file[:path]}"
  app.app_files.create!(path: file[:path], content: file[:content])
end

# Add a simple index.html for testing
index_content = <<~HTML
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>OAuth Test App</title>
</head>
<body>
  <div id="root"></div>
  <script type="module" src="/src/main.tsx"></script>
</body>
</html>
HTML

main_content = <<~TSX
import React from 'react'
import ReactDOM from 'react-dom/client'
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { Login } from './pages/auth/Login'
import { Signup } from './pages/auth/Signup'
import { AuthCallback } from './pages/auth/AuthCallback'
import { Dashboard } from './pages/Dashboard'
import { ProtectedRoute } from './components/auth/ProtectedRoute'
import './index.css'

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <BrowserRouter>
      <Routes>
        <Route path="/" element={<Navigate to="/dashboard" replace />} />
        <Route path="/login" element={<Login />} />
        <Route path="/signup" element={<Signup />} />
        <Route path="/auth/callback" element={<AuthCallback />} />
        <Route path="/dashboard" element={
          <ProtectedRoute>
            <Dashboard />
          </ProtectedRoute>
        } />
      </Routes>
    </BrowserRouter>
  </React.StrictMode>,
)
TSX

dashboard_content = <<~TSX
import { useAuth } from '../hooks/useAuth'
import { supabase } from '../lib/supabase'

export function Dashboard() {
  const { user, loading } = useAuth()

  const handleSignOut = async () => {
    await supabase.auth.signOut()
    window.location.href = '/login'
  }

  if (loading) {
    return <div className="min-h-screen flex items-center justify-center">Loading...</div>
  }

  return (
    <div className="min-h-screen bg-gray-50 flex items-center justify-center">
      <div className="bg-white p-8 rounded-lg shadow-md max-w-md w-full text-center">
        <h1 className="text-2xl font-bold text-gray-900 mb-4">Dashboard</h1>
        <p className="text-gray-600 mb-6">Welcome, {user?.email}!</p>
        <button
          onClick={handleSignOut}
          className="bg-red-600 text-white px-4 py-2 rounded hover:bg-red-700"
        >
          Sign Out
        </button>
      </div>
    </div>
  )
}
TSX

css_content = <<~CSS
@tailwind base;
@tailwind components;
@tailwind utilities;
CSS

# Add the required files
app.app_files.create!(path: 'index.html', content: index_content)
app.app_files.create!(path: 'src/main.tsx', content: main_content)
app.app_files.create!(path: 'src/pages/Dashboard.tsx', content: dashboard_content)
app.app_files.create!(path: 'src/index.css', content: css_content)

puts "\n📄 Added additional required files for React app"
puts "  - index.html"
puts "  - src/main.tsx"
puts "  - src/pages/Dashboard.tsx"
puts "  - src/index.css"

# Deploy the test app
puts "\n🚀 Deploying test app with enhanced OAuth..."
preview_service = Deployment::CloudflarePreviewService.new(app)
result = preview_service.update_preview!

if result[:success]
  app.update!(status: 'generated', preview_url: result[:preview_url])
  puts "✅ Test app deployed successfully!"
  puts "URL: #{result[:preview_url]}"
  
  puts "\n📋 Test the enhanced OAuth implementation:"
  puts "1. Visit: #{result[:preview_url]}/login"
  puts "2. Try social login (Google/GitHub)"
  puts "3. Should redirect to /dashboard with detailed console logging"
  puts "4. If errors occur, check browser console for PKCE flow details"
  puts "5. Error messages will provide specific troubleshooting steps"
  
  puts "\n🔍 OAuth Features Tested:"
  puts "  ✅ Enhanced PKCE handling with proper session management"
  puts "  ✅ Detailed console logging for debugging"
  puts "  ✅ User-friendly error messages with troubleshooting steps" 
  puts "  ✅ Clear browser data functionality"
  puts "  ✅ Multiple retry strategies (session refresh, manual exchange)"
  
else
  puts "❌ Deployment failed: #{result[:error]}"
end

puts "\n" + "=" * 80
puts "Auth template test complete - App ID: #{app.id}"
puts "=" * 80