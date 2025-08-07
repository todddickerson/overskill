#!/usr/bin/env ruby
# Final fix for App 57 with proper authentication
# Run with: bin/rails runner scripts/fix_app_57_auth_final.rb

puts "=== Final Fix for App 57 with Authentication ==="

app = App.find(57)
puts "App: #{app.name} (ID: #{app.id})"
puts "Team: #{app.team.name} (ID: #{app.team_id})"

# Step 1: Fix or create Auth component with proper team association
puts "\n1. Creating/updating Auth component..."
auth_file = app.app_files.find_by(path: 'src/components/Auth.jsx')
# Content must be set first
auth_content = <<~JSX
import { useState } from 'react'
import { supabase } from '../lib/supabase'

export function Auth({ onAuth }) {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [loading, setLoading] = useState(false)
  const [mode, setMode] = useState('signin')

  const handleSubmit = async (e) => {
    e.preventDefault()
    setLoading(true)
    
    try {
      if (mode === 'signup') {
        const { data, error } = await supabase.auth.signUp({
          email,
          password
        })
        if (error) throw error
        alert('Check your email for confirmation!')
      } else {
        const { data, error } = await supabase.auth.signInWithPassword({
          email,
          password
        })
        if (error) throw error
        if (data.user) onAuth(data.user)
      }
    } catch (error) {
      alert(error.message)
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50">
      <div className="max-w-md w-full space-y-8 p-8 bg-white rounded-lg shadow">
        <h2 className="text-center text-3xl font-extrabold text-gray-900">
          {mode === 'signin' ? 'Sign in' : 'Create account'}
        </h2>
        <form className="mt-8 space-y-6" onSubmit={handleSubmit}>
          <div className="space-y-4">
            <input
              type="email"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="w-full px-3 py-2 border border-gray-300 rounded-md"
              placeholder="Email address"
            />
            <input
              type="password"
              required
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="w-full px-3 py-2 border border-gray-300 rounded-md"
              placeholder="Password"
            />
          </div>
          <button
            type="submit"
            disabled={loading}
            className="w-full py-2 px-4 bg-indigo-600 text-white rounded-md hover:bg-indigo-700 disabled:opacity-50"
          >
            {loading ? 'Loading...' : (mode === 'signin' ? 'Sign in' : 'Sign up')}
          </button>
          <button
            type="button"
            onClick={() => setMode(mode === 'signin' ? 'signup' : 'signin')}
            className="w-full text-center text-indigo-600 hover:text-indigo-500"
          >
            {mode === 'signin' ? "Need an account? Sign up" : 'Have an account? Sign in'}
          </button>
        </form>
      </div>
    </div>
  )
}
JSX

if auth_file.nil?
  auth_file = app.app_files.create!(
    path: 'src/components/Auth.jsx',
    file_type: 'jsx',
    team_id: app.team_id,
    content: auth_content  # Set content immediately
  )
else
  auth_file.update!(content: auth_content)
end

# Auth content already set above
puts "✅ Created/updated Auth.jsx"

# Step 2: Update App.tsx with simplified authentication
puts "\n2. Updating App.tsx..."
app_tsx = app.app_files.find_by(path: 'src/App.tsx')
if app_tsx
  new_app_content = <<~TSX
import React, { useState, useEffect } from 'react'
import { supabase } from './lib/supabase'
import { Auth } from './components/Auth'

interface Todo {
  id: string
  text: string
  completed: boolean
  user_id: string
}

function App() {
  const [user, setUser] = useState<any>(null)
  const [todos, setTodos] = useState<Todo[]>([])
  const [newTodo, setNewTodo] = useState('')
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session } }) => {
      setUser(session?.user ?? null)
      setLoading(false)
    })

    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
      setUser(session?.user ?? null)
    })

    return () => subscription.unsubscribe()
  }, [])

  useEffect(() => {
    if (user) {
      fetchTodos()
    }
  }, [user])

  const fetchTodos = async () => {
    const { data } = await supabase
      .from('app_57_todos')
      .select('*')
      .eq('user_id', user.id)
      .order('created_at', { ascending: false })
    
    setTodos(data || [])
  }

  const addTodo = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!newTodo.trim()) return

    const { data } = await supabase
      .from('app_57_todos')
      .insert([{ 
        text: newTodo.trim(),
        completed: false,
        user_id: user.id
      }])
      .select()
      .single()
    
    if (data) {
      setTodos([data, ...todos])
      setNewTodo('')
    }
  }

  const toggleTodo = async (id: string, completed: boolean) => {
    await supabase
      .from('app_57_todos')
      .update({ completed: !completed })
      .eq('id', id)
      .eq('user_id', user.id)
    
    setTodos(todos.map(todo => 
      todo.id === id ? { ...todo, completed: !completed } : todo
    ))
  }

  const deleteTodo = async (id: string) => {
    await supabase
      .from('app_57_todos')
      .delete()
      .eq('id', id)
      .eq('user_id', user.id)
    
    setTodos(todos.filter(todo => todo.id !== id))
  }

  if (loading) {
    return <div className="min-h-screen bg-gray-50 flex items-center justify-center">Loading...</div>
  }

  if (!user) {
    return <Auth onAuth={setUser} />
  }

  return (
    <div className="min-h-screen bg-gray-50 py-8">
      <div className="max-w-md mx-auto bg-white rounded-lg shadow-lg p-6">
        <div className="flex justify-between items-center mb-6">
          <h1 className="text-2xl font-bold">My Todos</h1>
          <button
            onClick={() => supabase.auth.signOut()}
            className="text-sm text-gray-600 hover:text-gray-800"
          >
            Sign Out
          </button>
        </div>
        
        <form onSubmit={addTodo} className="mb-6">
          <div className="flex gap-2">
            <input
              type="text"
              value={newTodo}
              onChange={(e) => setNewTodo(e.target.value)}
              placeholder="Add a new task..."
              className="flex-1 px-4 py-2 border rounded-lg"
            />
            <button
              type="submit"
              className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700"
            >
              Add
            </button>
          </div>
        </form>

        <div className="space-y-2">
          {todos.length === 0 ? (
            <p className="text-center text-gray-500 py-8">No tasks yet. Add one above!</p>
          ) : (
            todos.map((todo) => (
              <div key={todo.id} className="flex items-center gap-3 p-3 border rounded-lg">
                <input
                  type="checkbox"
                  checked={todo.completed}
                  onChange={() => toggleTodo(todo.id, todo.completed)}
                  className="w-5 h-5"
                />
                <span className={\`flex-1 \${todo.completed ? 'line-through text-gray-500' : ''}\`}>
                  {todo.text}
                </span>
                <button
                  onClick={() => deleteTodo(todo.id)}
                  className="text-red-500 hover:text-red-700"
                >
                  Delete
                </button>
              </div>
            ))
          )}
        </div>
      </div>
    </div>
  )
}

export default App
TSX

  app_tsx.update!(content: new_app_content)
  puts "✅ Updated App.tsx with authentication"
else
  puts "❌ App.tsx not found"
end

# Step 3: Deploy the app
puts "\n3. Deploying to Cloudflare..."
begin
  app.update!(status: 'generated')
  
  deploy_service = Deployment::CloudflarePreviewService.new(app)
  result = deploy_service.update_preview!
  
  if result[:success]
    app.update!(
      status: 'published',
      preview_url: result[:preview_url],
      deployed_at: Time.current
    )
    puts "✅ Deployment successful!"
    puts "  Preview URL: #{result[:preview_url]}"
  else
    puts "❌ Deployment failed: #{result[:error]}"
  end
rescue => e
  puts "❌ Error: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end

# Step 4: Output SQL and summary
puts "\n" + "=" * 60
puts "SQL FOR SUPABASE"
puts "=" * 60

sql = <<~SQL
-- Create todos table for App 57
CREATE TABLE IF NOT EXISTS app_57_todos (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  text TEXT NOT NULL,
  completed BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_app_57_todos_user_id ON app_57_todos(user_id);
CREATE INDEX IF NOT EXISTS idx_app_57_todos_created_at ON app_57_todos(created_at DESC);

-- Enable RLS
ALTER TABLE app_57_todos ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Users can view own todos" ON app_57_todos FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own todos" ON app_57_todos FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own todos" ON app_57_todos FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own todos" ON app_57_todos FOR DELETE
  USING (auth.uid() = user_id);

-- Permissions
GRANT ALL ON app_57_todos TO authenticated;
GRANT ALL ON app_57_todos TO service_role;
SQL

puts sql

puts "\n" + "=" * 60
puts "SUMMARY"
puts "=" * 60
puts "✅ App 57 has been updated with:"
puts "  1. Authentication component (Auth.jsx)"
puts "  2. User login/signup functionality"
puts "  3. User-scoped todo queries"
puts "  4. Proper table name (app_57_todos)"
puts ""
puts "⚠️  IMPORTANT: Copy the SQL above and run it in Supabase SQL Editor"
puts ""
puts "📱 Test the app at: #{app.preview_url || 'https://preview-57.overskill.app'}"
puts "=" * 60