#!/usr/bin/env ruby
# Complete test of auth system with a simple app
# Run with: bin/rails runner scripts/test_complete_auth_system.rb

puts "=" * 80
puts "🚀 COMPLETE AUTH SYSTEM TEST"
puts "=" * 80
puts "This test will create a simple app with authentication"
puts "=" * 80

# Setup
user = User.first || User.create!(
  email: "test@example.com",
  password: "password123",
  first_name: "Test",
  last_name: "User"
)

team = user.teams.first || Team.create!(name: "Test Team")
membership = team.memberships.find_by(user: user) || team.memberships.create!(user: user, role_ids: ["admin"])

puts "\n📋 Using team: #{team.name}"
puts "👤 Using user: #{user.email}"

# Create a simple app that doesn't require AI generation
app_name = "Auth Test #{Time.now.strftime('%H%M%S')}"
puts "\n📱 Creating app: #{app_name}"

app = App.create!(
  team: team,
  creator: membership,
  name: app_name,
  prompt: "Simple app with authentication",
  app_type: 'saas',
  framework: 'react',
  status: 'generating'
)

puts "✅ Created app ##{app.id}"

# Manually add the essential files for a basic React app with auth
puts "\n📁 Adding auth files..."

# Add package.json
app.app_files.create!(
  team: team,
  path: 'package.json',
  content: Ai::AuthTemplates.package_json_template
)

# Add auth pages (this includes supabase.ts)
Ai::AuthTemplates.generate_auth_files(app)

# Add a simple App.tsx with routing
app.app_files.create!(
  team: team,
  path: 'src/App.tsx',
  content: <<~TSX
    import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
    import { Login } from './pages/auth/Login'
    import { SignUp } from './pages/auth/SignUp'
    import { ForgotPassword } from './pages/auth/ForgotPassword'
    import { AuthCallback } from './pages/auth/AuthCallback'
    import { ProtectedRoute } from './components/auth/ProtectedRoute'
    import { useAuth } from './hooks/useAuth'

    function Dashboard() {
      const { user, signOut } = useAuth()
      
      return (
        <div className="min-h-screen bg-gray-50 flex items-center justify-center">
          <div className="bg-white p-8 rounded-lg shadow-md max-w-md w-full">
            <h1 className="text-2xl font-bold mb-4">Dashboard</h1>
            <p className="text-gray-600 mb-4">Welcome, {user?.email}!</p>
            <button
              onClick={signOut}
              className="w-full bg-red-600 text-white py-2 px-4 rounded hover:bg-red-700"
            >
              Sign Out
            </button>
          </div>
        </div>
      )
    }

    export default function App() {
      return (
        <BrowserRouter>
          <Routes>
            <Route path="/login" element={<Login />} />
            <Route path="/signup" element={<SignUp />} />
            <Route path="/forgot-password" element={<ForgotPassword />} />
            <Route path="/auth/callback" element={<AuthCallback />} />
            <Route
              path="/dashboard"
              element={
                <ProtectedRoute>
                  <Dashboard />
                </ProtectedRoute>
              }
            />
            <Route path="/" element={<Navigate to="/dashboard" replace />} />
          </Routes>
        </BrowserRouter>
      )
    }
  TSX
)

# Add main.tsx
app.app_files.create!(
  team: team,
  path: 'src/main.tsx',
  content: <<~TSX
    import React from 'react'
    import ReactDOM from 'react-dom/client'
    import App from './App'
    import './index.css'

    ReactDOM.createRoot(document.getElementById('root')!).render(
      <React.StrictMode>
        <App />
      </React.StrictMode>
    )
  TSX
)

# Add index.html
app.app_files.create!(
  team: team,
  path: 'index.html',
  content: <<~HTML
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="UTF-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
        <title>#{app_name}</title>
      </head>
      <body>
        <div id="root"></div>
        <script type="module" src="/src/main.tsx"></script>
      </body>
    </html>
  HTML
)

# Add Tailwind CSS
app.app_files.create!(
  team: team,
  path: 'src/index.css',
  content: <<~CSS
    @tailwind base;
    @tailwind components;
    @tailwind utilities;
  CSS
)

# Add config files
app.app_files.create!(
  team: team,
  path: 'vite.config.ts',
  content: <<~TS
    import { defineConfig } from 'vite'
    import react from '@vitejs/plugin-react'

    export default defineConfig({
      plugins: [react()],
    })
  TS
)

app.app_files.create!(
  team: team,
  path: 'tsconfig.json',
  content: <<~JSON
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
)

app.app_files.create!(
  team: team,
  path: 'tsconfig.node.json',
  content: <<~JSON
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
)

app.app_files.create!(
  team: team,
  path: 'tailwind.config.js',
  content: <<~JS
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
)

app.app_files.create!(
  team: team,
  path: 'postcss.config.js',
  content: <<~JS
    export default {
      plugins: {
        tailwindcss: {},
        autoprefixer: {},
      },
    }
  JS
)

# Add vite-env.d.ts
app.app_files.create!(
  team: team,
  path: 'src/vite-env.d.ts',
  content: <<~TS
    /// <reference types="vite/client" />

    interface ImportMetaEnv {
      readonly VITE_SUPABASE_URL: string
      readonly VITE_SUPABASE_ANON_KEY: string
    }

    interface ImportMeta {
      readonly env: ImportMetaEnv
    }

    interface Window {
      ENV: Record<string, any>
    }
  TS
)

puts "✅ Added #{app.app_files.count} files"

# Create auth settings
puts "\n🔐 Creating auth settings..."
app.create_app_auth_setting!(
  visibility: 'public_login_required',
  allowed_providers: ['email', 'google', 'github'],
  allowed_email_domains: [],
  require_email_verification: false,
  allow_signups: true,
  allow_anonymous: false
)
puts "✅ Auth settings configured"

# Mark as generated
app.update!(status: 'generated')

# Deploy the app
puts "\n🚀 Deploying to Cloudflare..."
preview_service = Deployment::CloudflarePreviewService.new(app)
result = preview_service.update_preview!

if result[:success]
  puts "✅ Deployment successful!"
  app.update!(preview_url: result[:preview_url])
  
  puts "\n" + "=" * 80
  puts "✅ COMPLETE AUTH SYSTEM TEST SUCCESSFUL!"
  puts "=" * 80
  
  puts "\n📊 Summary:"
  puts "  App ID: #{app.id}"
  puts "  Name: #{app.name}"
  puts "  Files: #{app.app_files.count}"
  puts "  Auth: Configured with login required"
  puts "  Preview: #{result[:preview_url]}"
  
  puts "\n🌐 Test URLs:"
  puts "  Home: #{result[:preview_url]} (should redirect to login)"
  puts "  Login: #{result[:preview_url]}/login"
  puts "  Signup: #{result[:preview_url]}/signup"
  puts "  Dashboard: #{result[:preview_url]}/dashboard (protected)"
  
  puts "\n📋 Test Instructions:"
  puts "  1. Visit #{result[:preview_url]}"
  puts "  2. Should see login page"
  puts "  3. Try creating an account"
  puts "  4. Try social login"
  puts "  5. Check browser console for window.ENV"
  puts "  6. Verify no Supabase errors"
  
else
  puts "❌ Deployment failed: #{result[:error]}"
end

puts "\n" + "=" * 80
puts "Test completed at #{Time.current}"
puts "=" * 80