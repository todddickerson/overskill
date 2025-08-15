module Ai
  # DEPRECATED: This service is used by V4/V4Enhanced only.
  # V5 uses templates directly from templates/overskill_20250728
  # Do not use for new development.
  class SharedTemplateService
    def initialize(app)
      @app = app
      @team = app.team
    end
    
    def generate_foundation_files
      Rails.logger.info "[SharedTemplateService] Generating foundation files for app ##{@app.id}"
      
      files_created = []
      
      # Generate each category of templates
      files_created += generate_core_config_files
      files_created += generate_entry_point_files
      files_created += generate_database_files
      files_created += generate_auth_files
      files_created += generate_routing_files
      files_created += generate_layout_files
      
      Rails.logger.info "[SharedTemplateService] Generated #{files_created.size} foundation files"
      
      # Return data format expected by AppBuilderV4Enhanced
      files_created.map do |file_path|
        app_file = @app.app_files.find_by(path: file_path)
        {
          path: file_path,
          content: app_file&.content || "// File content for #{file_path}"
        }
      end
    end
    
    # Keep the old method name for backward compatibility
    alias_method :generate_core_files, :generate_foundation_files
    
    private
    
    def generate_core_config_files
      files = []
      
      # package.json
      create_file('package.json', package_json_template)
      files << 'package.json'
      
      # vite.config.ts
      create_file('vite.config.ts', vite_config_template)
      files << 'vite.config.ts'
      
      # tsconfig.json
      create_file('tsconfig.json', tsconfig_template)
      files << 'tsconfig.json'
      
      # tsconfig.node.json
      create_file('tsconfig.node.json', tsconfig_node_template)
      files << 'tsconfig.node.json'
      
      # tailwind.config.js
      create_file('tailwind.config.js', tailwind_config_template)
      files << 'tailwind.config.js'
      
      # postcss.config.js
      create_file('postcss.config.js', postcss_config_template)
      files << 'postcss.config.js'
      
      # .env.example
      create_file('.env.example', env_example_template)
      files << '.env.example'
      
      files
    end
    
    def generate_entry_point_files
      files = []
      
      # index.html
      create_file('index.html', index_html_template)
      files << 'index.html'
      
      # src/main.tsx - CRITICAL entry point
      create_file('src/main.tsx', main_tsx_template)
      files << 'src/main.tsx'
      
      # src/index.css
      create_file('src/index.css', index_css_template)
      files << 'src/index.css'
      
      # src/lib/common-icons.ts - Pre-exported commonly used icons
      create_file('src/lib/common-icons.ts', common_icons_template)
      files << 'src/lib/common-icons.ts'
      
      # src/App.tsx
      create_file('src/App.tsx', app_tsx_template)
      files << 'src/App.tsx'
      
      files
    end
    
    def generate_database_files
      files = []
      
      # src/lib/supabase.ts
      create_file('src/lib/supabase.ts', supabase_client_template)
      files << 'src/lib/supabase.ts'
      
      # src/lib/app-scoped-db.ts
      create_file('src/lib/app-scoped-db.ts', app_scoped_db_template)
      files << 'src/lib/app-scoped-db.ts'
      
      # src/types/database.ts
      create_file('src/types/database.ts', database_types_template)
      files << 'src/types/database.ts'
      
      files
    end
    
    def generate_auth_files
      files = []
      
      # src/hooks/useAuth.ts
      create_file('src/hooks/useAuth.ts', use_auth_hook_template)
      files << 'src/hooks/useAuth.ts'
      
      # src/components/auth/AuthForm.tsx
      create_file('src/components/auth/AuthForm.tsx', auth_form_template)
      files << 'src/components/auth/AuthForm.tsx'
      
      # src/components/auth/ProtectedRoute.tsx
      create_file('src/components/auth/ProtectedRoute.tsx', protected_route_template)
      files << 'src/components/auth/ProtectedRoute.tsx'
      
      files
    end
    
    def generate_routing_files
      files = []
      
      # src/router.tsx
      create_file('src/router.tsx', router_template)
      files << 'src/router.tsx'
      
      # src/pages/Home.tsx
      create_file('src/pages/Home.tsx', home_page_template)
      files << 'src/pages/Home.tsx'
      
      # src/pages/auth/Login.tsx
      create_file('src/pages/auth/Login.tsx', login_page_template)
      files << 'src/pages/auth/Login.tsx'
      
      files
    end
    
    def generate_layout_files
      files = []
      
      # src/components/Layout.tsx
      create_file('src/components/Layout.tsx', layout_template)
      files << 'src/components/Layout.tsx'
      
      # src/components/Navigation.tsx
      create_file('src/components/Navigation.tsx', navigation_template)
      files << 'src/components/Navigation.tsx'
      
      files
    end
    
    def create_file(path, content)
      # Process template variables
      processed_content = process_template_variables(content)
      
      # Ensure content is not blank
      if processed_content.blank?
        Rails.logger.error "[SharedTemplateService] Blank content for file: #{path}"
        processed_content = "// Placeholder for #{path}"
      end
      
      # Create or update the file
      existing_file = @app.app_files.find_by(path: path)
      
      if existing_file
        existing_file.update!(content: processed_content)
      else
        @app.app_files.create!(
          path: path,
          content: processed_content,
          team: @team
        )
      end
      
      Rails.logger.debug "[SharedTemplateService] Created file: #{path}"
    end
    
    def process_template_variables(content)
      content
        .gsub('{{APP_NAME}}', @app.name)
        .gsub('{{APP_ID}}', @app.id.to_s)
        .gsub('{{APP_SLUG}}', @app.name.parameterize)
        .gsub('{{TEAM_ID}}', @team.id.to_s)
    end
    
    # Template content methods
    
    def package_json_template
      <<~JSON
        {
          "name": "app-#{@app.id}",
          "version": "1.0.0",
          "type": "module",
          "scripts": {
            "dev": "vite",
            "build": "tsc && vite build",
            "preview": "vite preview",
            "typecheck": "tsc --noEmit"
          },
          "dependencies": {
            "react": "^18.2.0",
            "react-dom": "^18.2.0",
            "react-router-dom": "^6.20.0",
            "@supabase/supabase-js": "^2.39.0",
            "@supabase/auth-ui-react": "^0.4.6",
            "@supabase/auth-ui-shared": "^0.1.8"
          },
          "devDependencies": {
            "@types/react": "^18.2.0",
            "@types/react-dom": "^18.2.0",
            "@typescript-eslint/eslint-plugin": "^6.13.0",
            "@typescript-eslint/parser": "^6.13.0",
            "@vitejs/plugin-react": "^4.2.0",
            "autoprefixer": "^10.4.16",
            "eslint": "^8.55.0",
            "eslint-plugin-react-hooks": "^4.6.0",
            "eslint-plugin-react-refresh": "^0.4.5",
            "postcss": "^8.4.32",
            "tailwindcss": "^3.3.6",
            "typescript": "^5.3.3",
            "vite": "^5.0.7"
          }
        }
      JSON
    end
    
    def vite_config_template
      <<~TS
        import { defineConfig } from 'vite'
        import react from '@vitejs/plugin-react'
        import path from 'path'
        
        export default defineConfig({
          plugins: [react()],
          resolve: {
            alias: {
              '@': path.resolve(__dirname, './src'),
            },
          },
          server: {
            port: 3000,
            open: true,
          },
          build: {
            outDir: 'dist',
            sourcemap: true,
            rollupOptions: {
              output: {
                manualChunks: {
                  vendor: ['react', 'react-dom', 'react-router-dom'],
                  supabase: ['@supabase/supabase-js', '@supabase/auth-ui-react'],
                },
              },
            },
          },
        })
      TS
    end
    
    def tsconfig_node_template
      <<~JSON
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
    end
    
    def tsconfig_template
      <<~JSON
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
            "noFallthroughCasesInSwitch": true,
            "paths": {
              "@/*": ["./src/*"]
            }
          },
          "include": ["src"],
          "references": [{ "path": "./tsconfig.node.json" }]
        }
      JSON
    end
    
    def tailwind_config_template
      <<~JS
        /** @type {import('tailwindcss').Config} */
        export default {
          content: [
            "./index.html",
            "./src/**/*.{js,ts,jsx,tsx}",
          ],
          theme: {
            extend: {
              colors: {
                primary: {
                  50: '#eff6ff',
                  100: '#dbeafe',
                  200: '#bfdbfe',
                  300: '#93c5fd',
                  400: '#60a5fa',
                  500: '#3b82f6',
                  600: '#2563eb',
                  700: '#1d4ed8',
                  800: '#1e40af',
                  900: '#1e3a8a',
                },
              },
            },
          },
          plugins: [],
        }
      JS
    end
    
    def postcss_config_template
      <<~JS
        export default {
          plugins: {
            tailwindcss: {},
            autoprefixer: {},
          },
        }
      JS
    end
    
    def env_example_template
      <<~ENV
        # Supabase Configuration
        VITE_SUPABASE_URL=your_supabase_url
        VITE_SUPABASE_ANON_KEY=your_supabase_anon_key
        
        # App Configuration
        VITE_APP_ID={{APP_ID}}
        VITE_APP_NAME={{APP_NAME}}
      ENV
    end
    
    def index_html_template
      <<~HTML
        <!DOCTYPE html>
        <html lang="en">
          <head>
            <meta charset="UTF-8" />
            <link rel="icon" type="image/svg+xml" href="/vite.svg" />
            <meta name="viewport" content="width=device-width, initial-scale=1.0" />
            <title>{{APP_NAME}}</title>
          </head>
          <body>
            <div id="root"></div>
            <script type="module" src="/src/main.tsx"></script>
          </body>
        </html>
      HTML
    end
    
    def main_tsx_template
      <<~TSX
        import React from 'react'
        import ReactDOM from 'react-dom/client'
        import App from './App'
        import './index.css'
        
        ReactDOM.createRoot(document.getElementById('root')!).render(
          <React.StrictMode>
            <App />
          </React.StrictMode>,
        )
      TSX
    end
    
    def index_css_template
      <<~CSS
        @tailwind base;
        @tailwind components;
        @tailwind utilities;
        
        @layer base {
          body {
            @apply bg-gray-50 text-gray-900;
          }
        }
        
        @layer components {
          .btn-primary {
            @apply bg-primary-600 text-white px-4 py-2 rounded-lg hover:bg-primary-700 transition-colors;
          }
          
          .btn-secondary {
            @apply bg-gray-200 text-gray-900 px-4 py-2 rounded-lg hover:bg-gray-300 transition-colors;
          }
        }
      CSS
    end
    
    def common_icons_template
      <<~TS
        /**
         * Commonly used Lucide React icons - pre-exported for convenience
         * This helps prevent missing import errors for frequently used icons
         * 
         * Usage:
         * import { Menu, X, Check, Shield } from '@/lib/common-icons'
         * 
         * Or import all:
         * import * as Icons from '@/lib/common-icons'
         */
        
        // Re-export all commonly used icons
        export {
          // Navigation & UI
          Menu, X, ChevronDown, ChevronUp, ChevronLeft, ChevronRight,
          ArrowLeft, ArrowRight, ArrowUp, ArrowDown,
          
          // Actions
          Check, Plus, Minus, Edit, Trash, Save, Download, Upload, Share, Copy,
          
          // Status & Info
          Info, AlertCircle, CheckCircle, XCircle, HelpCircle,
          
          // Common Objects
          User, Users, Home, Settings, Search, Filter, Calendar, Clock,
          Mail, Phone, MapPin, Globe,
          
          // Business & Features
          Shield, Lock, Unlock, Key, CreditCard, DollarSign,
          ShoppingCart, Package, Gift,
          
          // Media
          Image, Camera, Video, Mic, Volume, VolumeX, Play, Pause,
          
          // Tech & Development
          Code, Terminal, Cpu, Database, Cloud, Wifi,
          
          // Social
          Github, Twitter, Linkedin, Facebook,
          
          // Premium/Marketing
          Zap, Crown, Star, Heart, ThumbsUp, TrendingUp,
          Rocket, Target, Award, Trophy,
          
          // Loading & Progress
          Loader, Loader2, RefreshCw
        } from 'lucide-react'
        
        // Re-export all icons for cases where specific ones are needed
        export * from 'lucide-react'
      TS
    end
    
    def app_tsx_template
      <<~TSX
        import { BrowserRouter } from 'react-router-dom'
        import { Router } from './router'
        import { useAuth } from './hooks/useAuth'
        
        function App() {
          const { loading } = useAuth()
          
          if (loading) {
            return (
              <div className="min-h-screen flex items-center justify-center">
                <div className="text-lg">Loading...</div>
              </div>
            )
          }
          
          return (
            <BrowserRouter>
              <Router />
            </BrowserRouter>
          )
        }
        
        export default App
      TSX
    end
    
    def supabase_client_template
      <<~TS
        import { createClient } from '@supabase/supabase-js'
        
        // Use window.APP_CONFIG injected by the Worker
        declare global {
          interface Window {
            APP_CONFIG?: {
              supabaseUrl: string
              supabaseAnonKey: string
              appId: string
              environment: string
              customVars: Record<string, string>
            }
          }
        }
        
        const supabaseUrl = window.APP_CONFIG?.supabaseUrl || ''
        const supabaseAnonKey = window.APP_CONFIG?.supabaseAnonKey || ''
        
        if (!supabaseUrl || !supabaseAnonKey) {
          console.error('Supabase credentials not configured')
          console.log('APP_CONFIG:', window.APP_CONFIG)
        }
        
        export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
          auth: {
            persistSession: true,
            autoRefreshToken: true,
          },
        })
      TS
    end
    
    def app_scoped_db_template
      <<~TS
        import { supabase } from './supabase'
        
        /**
         * App-scoped database wrapper
         * Automatically prefixes table names with app ID for multi-tenant isolation
         */
        export class AppScopedDatabase {
          private appId: string
          
          constructor(appId?: string) {
            this.appId = appId || import.meta.env.VITE_APP_ID || '{{APP_ID}}'
          }
          
          /**
           * Access a table with app-scoped naming
           * @example db.from('todos') // Actually queries app_123_todos
           */
          from(table: string) {
            const scopedTable = `app_${this.appId}_${table}`
            
            if (import.meta.env.DEV) {
              console.log(`[DB] Querying table: ${scopedTable}`)
            }
            
            return supabase.from(scopedTable)
          }
          
          /**
           * Get the actual table name with app prefix
           */
          getTableName(table: string): string {
            return `app_${this.appId}_${table}`
          }
          
          /**
           * Direct access to Supabase client for auth and other operations
           */
          get client() {
            return supabase
          }
        }
        
        // Export singleton instance
        export const db = new AppScopedDatabase()
      TS
    end
    
    def database_types_template
      <<~TS
        /**
         * Database types for {{APP_NAME}}
         * Add your app-specific types here
         */
        
        export interface User {
          id: string
          email: string
          created_at: string
          updated_at: string
        }
        
        export interface BaseRecord {
          id: string
          created_at: string
          updated_at: string
          app_id: string
          user_id?: string
        }
        
        // Add your app-specific types below
      TS
    end
    
    def use_auth_hook_template
      <<~TSX
        import { useEffect, useState } from 'react'
        import { User } from '@supabase/supabase-js'
        import { supabase } from '@/lib/supabase'
        
        export function useAuth() {
          const [user, setUser] = useState<User | null>(null)
          const [loading, setLoading] = useState(true)
          
          useEffect(() => {
            // Get initial session
            supabase.auth.getSession().then(({ data: { session } }) => {
              setUser(session?.user ?? null)
              setLoading(false)
            })
            
            // Listen for auth changes
            const { data: { subscription } } = supabase.auth.onAuthStateChange((event, session) => {
              setUser(session?.user ?? null)
            })
            
            return () => subscription.unsubscribe()
          }, [])
          
          const signIn = async (email: string, password: string) => {
            const { error } = await supabase.auth.signInWithPassword({
              email,
              password,
            })
            return { error }
          }
          
          const signUp = async (email: string, password: string) => {
            const { error } = await supabase.auth.signUp({
              email,
              password,
            })
            return { error }
          }
          
          const signOut = async () => {
            const { error } = await supabase.auth.signOut()
            return { error }
          }
          
          return {
            user,
            loading,
            signIn,
            signUp,
            signOut,
          }
        }
      TSX
    end
    
    def auth_form_template
      <<~TSX
        import { useState } from 'react'
        import { useAuth } from '@/hooks/useAuth'
        import { useNavigate } from 'react-router-dom'
        
        interface AuthFormProps {
          mode: 'signin' | 'signup'
        }
        
        export function AuthForm({ mode }: AuthFormProps) {
          const [email, setEmail] = useState('')
          const [password, setPassword] = useState('')
          const [error, setError] = useState<string | null>(null)
          const [loading, setLoading] = useState(false)
          
          const { signIn, signUp } = useAuth()
          const navigate = useNavigate()
          
          const handleSubmit = async (e: React.FormEvent) => {
            e.preventDefault()
            setError(null)
            setLoading(true)
            
            const { error } = mode === 'signin' 
              ? await signIn(email, password)
              : await signUp(email, password)
            
            if (error) {
              setError(error.message)
              setLoading(false)
            } else {
              navigate('/')
            }
          }
          
          return (
            <form onSubmit={handleSubmit} className="space-y-4 w-full max-w-md">
              <div>
                <label htmlFor="email" className="block text-sm font-medium mb-1">
                  Email
                </label>
                <input
                  id="email"
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-primary-500"
                  required
                />
              </div>
              
              <div>
                <label htmlFor="password" className="block text-sm font-medium mb-1">
                  Password
                </label>
                <input
                  id="password"
                  type="password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-primary-500"
                  required
                />
              </div>
              
              {error && (
                <div className="text-red-600 text-sm">{error}</div>
              )}
              
              <button
                type="submit"
                disabled={loading}
                className="w-full btn-primary disabled:opacity-50"
              >
                {loading ? 'Loading...' : mode === 'signin' ? 'Sign In' : 'Sign Up'}
              </button>
            </form>
          )
        }
      TSX
    end
    
    def protected_route_template
      <<~TSX
        import { Navigate } from 'react-router-dom'
        import { useAuth } from '@/hooks/useAuth'
        
        interface ProtectedRouteProps {
          children: React.ReactNode
        }
        
        export function ProtectedRoute({ children }: ProtectedRouteProps) {
          const { user, loading } = useAuth()
          
          if (loading) {
            return (
              <div className="min-h-screen flex items-center justify-center">
                <div className="text-lg">Loading...</div>
              </div>
            )
          }
          
          if (!user) {
            return <Navigate to="/login" replace />
          }
          
          return <>{children}</>
        }
      TSX
    end
    
    def router_template
      <<~TSX
        import { Routes, Route } from 'react-router-dom'
        import { Layout } from '@/components/Layout'
        import { ProtectedRoute } from '@/components/auth/ProtectedRoute'
        import Home from '@/pages/Home'
        import Login from '@/pages/auth/Login'
        
        export function Router() {
          return (
            <Routes>
              <Route path="/login" element={<Login />} />
              
              <Route element={<Layout />}>
                <Route
                  path="/"
                  element={
                    <ProtectedRoute>
                      <Home />
                    </ProtectedRoute>
                  }
                />
                {/* Add more protected routes here */}
              </Route>
            </Routes>
          )
        }
      TSX
    end
    
    def home_page_template
      <<~TSX
        import { useAuth } from '@/hooks/useAuth'
        
        export default function Home() {
          const { user } = useAuth()
          
          return (
            <div className="container mx-auto px-4 py-8">
              <h1 className="text-3xl font-bold mb-4">Welcome to {{APP_NAME}}</h1>
              <p className="text-gray-600 mb-8">
                You're signed in as {user?.email}
              </p>
              
              <div className="bg-white rounded-lg shadow p-6">
                <h2 className="text-xl font-semibold mb-4">Get Started</h2>
                <p className="text-gray-600">
                  This is your app's home page. Start building your features here!
                </p>
              </div>
            </div>
          )
        }
      TSX
    end
    
    def login_page_template
      <<~TSX
        import { Link } from 'react-router-dom'
        import { AuthForm } from '@/components/auth/AuthForm'
        import { useState } from 'react'
        
        export default function Login() {
          const [mode, setMode] = useState<'signin' | 'signup'>('signin')
          
          return (
            <div className="min-h-screen flex items-center justify-center bg-gray-50">
              <div className="max-w-md w-full space-y-8 p-8 bg-white rounded-lg shadow">
                <div>
                  <h2 className="text-center text-3xl font-bold">
                    {mode === 'signin' ? 'Sign in to your account' : 'Create new account'}
                  </h2>
                </div>
                
                <AuthForm mode={mode} />
                
                <div className="text-center">
                  <button
                    onClick={() => setMode(mode === 'signin' ? 'signup' : 'signin')}
                    className="text-primary-600 hover:text-primary-700"
                  >
                    {mode === 'signin' 
                      ? "Don't have an account? Sign up" 
                      : 'Already have an account? Sign in'}
                  </button>
                </div>
              </div>
            </div>
          )
        }
      TSX
    end
    
    def layout_template
      <<~TSX
        import { Outlet } from 'react-router-dom'
        import { Navigation } from './Navigation'
        
        export function Layout() {
          return (
            <div className="min-h-screen bg-gray-50">
              <Navigation />
              <main>
                <Outlet />
              </main>
            </div>
          )
        }
      TSX
    end
    
    def navigation_template
      <<~TSX
        import { Link } from 'react-router-dom'
        import { useAuth } from '@/hooks/useAuth'
        
        export function Navigation() {
          const { user, signOut } = useAuth()
          
          const handleSignOut = async () => {
            await signOut()
          }
          
          return (
            <nav className="bg-white shadow">
              <div className="container mx-auto px-4">
                <div className="flex justify-between items-center h-16">
                  <Link to="/" className="text-xl font-bold text-primary-600">
                    {{APP_NAME}}
                  </Link>
                  
                  <div className="flex items-center space-x-4">
                    {user && (
                      <>
                        <span className="text-gray-600">{user.email}</span>
                        <button
                          onClick={handleSignOut}
                          className="btn-secondary text-sm"
                        >
                          Sign Out
                        </button>
                      </>
                    )}
                  </div>
                </div>
              </div>
            </nav>
          )
        }
      TSX
    end
  end
end