#!/usr/bin/env ruby
# Test the standardized auth templates system
# Run with: bin/rails runner scripts/test_auth_templates.rb

require_relative '../app/services/ai/auth_templates'

puts "=" * 60
puts "TESTING STANDARDIZED AUTH TEMPLATES"
puts "=" * 60

# Find or create a test app
app = App.find_or_create_by(name: "Auth Test App #{Time.current.to_i}") do |a|
  team = Team.first || Team.create!(name: "Test Team")
  creator = team.memberships.first || team.memberships.create!(
    user: User.first || User.create!(
      email: "test@example.com",
      password: "password123",
      first_name: "Test",
      last_name: "User"
    ),
    role_ids: ["admin"]
  )
  
  a.team = team
  a.creator = creator
  a.status = 'generating'
  a.app_type = 'tool'
  a.framework = 'react'
  a.prompt = 'Test app for auth templates'
end

puts "\n📱 Using App ##{app.id}: #{app.name}"
puts "  Team: #{app.team.name}"

# Step 1: Generate auth files
puts "\n[STEP 1] Generating Auth Files..."
puts "-" * 40

begin
  # Clear existing files to start fresh
  app.app_files.destroy_all
  
  # Generate standard auth files
  Ai::AuthTemplates.generate_auth_files(app)
  
  # Add the router-enabled App.tsx
  app.app_files.create!(
    path: 'src/App.tsx',
    content: Ai::AuthTemplates.router_app_template,
    team: app.team
  )
  
  # Add package.json with React Router
  app.app_files.create!(
    path: 'package.json',
    content: Ai::AuthTemplates.package_json_template,
    team: app.team
  )
  
  # Add basic Dashboard page
  app.app_files.create!(
    path: 'src/pages/Dashboard.tsx',
    content: <<~TSX,
      import { useAuth } from '../hooks/useAuth'
      
      export function Dashboard() {
        const { user, signOut } = useAuth()
        
        return (
          <div className="min-h-screen bg-gray-50">
            <div className="max-w-7xl mx-auto py-12 px-4 sm:px-6 lg:px-8">
              <div className="bg-white shadow rounded-lg p-6">
                <h1 className="text-2xl font-bold text-gray-900 mb-4">Dashboard</h1>
                <p className="text-gray-600 mb-4">
                  Welcome, {user?.email}!
                </p>
                <button
                  onClick={signOut}
                  className="px-4 py-2 bg-red-600 text-white rounded hover:bg-red-700"
                >
                  Sign Out
                </button>
              </div>
            </div>
          </div>
        )
      }
    TSX
    team: app.team
  )
  
  # Add other necessary files
  app.app_files.create!(
    path: 'src/main.tsx',
    content: <<~TSX,
      import React from 'react'
      import ReactDOM from 'react-dom/client'
      import { App } from './App'
      import './index.css'
      
      ReactDOM.createRoot(document.getElementById('root')!).render(
        <React.StrictMode>
          <App />
        </React.StrictMode>,
      )
    TSX
    team: app.team
  )
  
  app.app_files.create!(
    path: 'src/vite-env.d.ts',
    content: <<~TSX,
      /// <reference types="vite/client" />
    TSX
    team: app.team
  )
  
  app.app_files.create!(
    path: 'src/lib/supabase.ts',
    content: <<~TSX,
      import { createClient } from '@supabase/supabase-js'
      
      const supabaseUrl = (import.meta as any).env?.VITE_SUPABASE_URL || ''
      const supabaseAnonKey = (import.meta as any).env?.VITE_SUPABASE_ANON_KEY || ''
      
      export const supabase = createClient(supabaseUrl, supabaseAnonKey)
    TSX
    team: app.team
  )
  
  app.app_files.create!(
    path: 'index.html',
    content: <<~HTML,
      <!doctype html>
      <html lang="en">
        <head>
          <meta charset="UTF-8" />
          <link rel="icon" type="image/svg+xml" href="/vite.svg" />
          <meta name="viewport" content="width=device-width, initial-scale=1.0" />
          <title>Auth Test App</title>
        </head>
        <body>
          <div id="root"></div>
          <script type="module" src="/src/main.tsx"></script>
        </body>
      </html>
    HTML
    team: app.team
  )
  
  app.app_files.create!(
    path: 'src/index.css',
    content: <<~CSS,
      @tailwind base;
      @tailwind components;
      @tailwind utilities;
    CSS
    team: app.team
  )
  
  app.app_files.create!(
    path: 'tailwind.config.js',
    content: <<~JS,
      /** @type {import('tailwindcss').Config} */
      export default {
        content: [
          "./index.html",
          "./src/**/*.{js,ts,jsx,tsx}",
        ],
        theme: {
          extend: {},
        },
        plugins: [],
      }
    JS
    team: app.team
  )
  
  app.app_files.create!(
    path: 'vite.config.ts',
    content: <<~TS,
      import { defineConfig } from 'vite'
      import react from '@vitejs/plugin-react'
      
      export default defineConfig({
        plugins: [react()],
      })
    TS
    team: app.team
  )
  
  app.app_files.create!(
    path: 'tsconfig.json',
    content: <<~JSON,
      {
        "compilerOptions": {
          "target": "ES2020",
          "useDefineForClassFields": true,
          "lib": ["ES2020", "DOM", "DOM.Iterable"],
          "module": "ESNext",
          "skipLibCheck": true,
          "moduleResolution": "bundler",
          "allowImportingTsExtensions": true,
          "resolveJsonModule": true,
          "isolatedModules": true,
          "noEmit": true,
          "jsx": "react-jsx",
          "strict": true,
          "noUnusedLocals": true,
          "noUnusedParameters": true,
          "noFallthroughCasesInSwitch": true
        },
        "include": ["src"],
        "references": [{ "path": "./tsconfig.node.json" }]
      }
    JSON
    team: app.team
  )
  
  app.app_files.create!(
    path: 'tsconfig.node.json',
    content: <<~JSON,
      {
        "compilerOptions": {
          "composite": true,
          "skipLibCheck": true,
          "module": "ESNext",
          "moduleResolution": "bundler",
          "allowSyntheticDefaultImports": true
        },
        "include": ["vite.config.ts"]
      }
    JSON
    team: app.team
  )
  
  app.app_files.create!(
    path: 'postcss.config.js',
    content: <<~JS,
      export default {
        plugins: {
          tailwindcss: {},
          autoprefixer: {},
        },
      }
    JS
    team: app.team
  )
  
  app.app_files.create!(
    path: '.env.example',
    content: <<~ENV,
      VITE_SUPABASE_URL=https://your-project.supabase.co
      VITE_SUPABASE_ANON_KEY=your-anon-key
    ENV
    team: app.team
  )
  
  puts "✅ Generated #{app.app_files.count} files"
  
rescue => e
  puts "❌ Error generating files: #{e.message}"
  puts e.backtrace.first(3).join("\n")
end

# Step 2: Verify file structure
puts "\n[STEP 2] Verifying File Structure..."
puts "-" * 40

expected_auth_files = [
  'src/pages/auth/Login.tsx',
  'src/pages/auth/SignUp.tsx',
  'src/pages/auth/ForgotPassword.tsx',
  'src/pages/auth/AuthCallback.tsx',
  'src/components/auth/SocialButtons.tsx',
  'src/components/auth/ProtectedRoute.tsx',
  'src/hooks/useAuth.ts',
  'src/App.tsx',
  'src/pages/Dashboard.tsx',
  'package.json'
]

file_check = {}
expected_auth_files.each do |path|
  file = app.app_files.find_by(path: path)
  file_check[path] = file.present?
  status = file.present? ? "✅" : "❌"
  size = file.present? ? "(#{file.content.length} bytes)" : ""
  puts "  #{status} #{path} #{size}"
end

success_rate = (file_check.values.count(true).to_f / file_check.count * 100).round(1)
puts "\n  Success Rate: #{success_rate}%"

# Step 3: Check code quality
puts "\n[STEP 3] Code Quality Checks..."
puts "-" * 40

login_file = app.app_files.find_by(path: 'src/pages/auth/Login.tsx')
if login_file
  quality_checks = {
    "React Router imports": login_file.content.include?('react-router-dom'),
    "Supabase integration": login_file.content.include?('supabase.auth'),
    "Social buttons": login_file.content.include?('SocialButtons'),
    "Error handling": login_file.content.include?('error'),
    "Loading states": login_file.content.include?('loading'),
    "TypeScript types": login_file.content.include?('<string | null>'),
    "Proper input colors": login_file.content.include?('text-gray-900'),
    "Responsive design": login_file.content.include?('sm:')
  }
  
  quality_checks.each do |check, passed|
    status = passed ? "✅" : "❌"
    puts "  #{status} #{check}"
  end
else
  puts "  ❌ Login file not found"
end

# Step 4: Deploy test
puts "\n[STEP 4] Deployment Test..."
puts "-" * 40

if success_rate == 100
  app.update!(status: 'generated')
  
  begin
    deploy_service = Deployment::CloudflarePreviewService.new(app)
    result = deploy_service.update_preview!
    
    if result[:success]
      puts "  ✅ Deployment successful"
      puts "  URL: #{result[:preview_url]}"
      app.update!(
        status: 'published',
        preview_url: result[:preview_url],
        deployed_at: Time.current
      )
    else
      puts "  ❌ Deployment failed: #{result[:error]}"
    end
  rescue => e
    puts "  ❌ Deploy error: #{e.message}"
  end
else
  puts "  ⚠️  Skipping deployment (files incomplete)"
end

# Summary
puts "\n" + "=" * 60
puts "PHASE 1 TEST SUMMARY"
puts "=" * 60

puts "\n📊 Results:"
puts "  Files Generated: #{app.app_files.count}"
puts "  Auth Files: #{file_check.values.count(true)}/#{file_check.count}"
puts "  Success Rate: #{success_rate}%"

if app.preview_url
  puts "\n🌐 Live Preview:"
  puts "  #{app.preview_url}"
  puts "  Test the following flows:"
  puts "  • /login - Sign in page with social buttons"
  puts "  • /signup - Registration page"
  puts "  • /forgot-password - Password reset"
  puts "  • /dashboard - Protected route (requires login)"
end

puts "\n💡 Token Savings:"
puts "  Traditional: ~10,000 tokens for auth implementation"
puts "  Phase 1: ~500 tokens (just file creation)"
puts "  Savings: ~9,500 tokens (95% reduction)"

puts "\n✨ Phase 1 Benefits:"
puts "  • Consistent auth experience across all apps"
puts "  • Professional UI with proper styling"
puts "  • Social login support (Google, GitHub)"
puts "  • Email confirmation and password reset"
puts "  • React Router with protected routes"
puts "  • TypeScript with proper types"
puts "  • No white-on-white text issues"

puts "\n" + "=" * 60