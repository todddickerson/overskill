#!/usr/bin/env ruby
# Simple regeneration of App 57 with authentication
# Run with: bin/rails runner scripts/simple_regenerate_57.rb

puts "=== Simple Regeneration of App 57 ==="

app = App.find(57)
puts "App: #{app.name} (ID: #{app.id})"

# Step 1: Create auth component
puts "\n1. Creating Auth component..."
auth_file = app.app_files.find_or_create_by!(path: 'src/components/Auth.jsx') do |f|
  f.file_type = 'jsx'
end

auth_content = <<~JSX
import { useState, useEffect } from 'react'
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
          password,
          options: {
            emailRedirectTo: window.location.origin
          }
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
        <div>
          <h2 className="text-center text-3xl font-extrabold text-gray-900">
            {mode === 'signin' ? 'Sign in' : 'Create account'}
          </h2>
        </div>
        <form className="mt-8 space-y-6" onSubmit={handleSubmit}>
          <div className="space-y-4">
            <input
              type="email"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="appearance-none relative block w-full px-3 py-2 border border-gray-300 placeholder-gray-500 text-gray-900 rounded-md focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 focus:z-10 sm:text-sm"
              placeholder="Email address"
            />
            <input
              type="password"
              required
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="appearance-none relative block w-full px-3 py-2 border border-gray-300 placeholder-gray-500 text-gray-900 rounded-md focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 focus:z-10 sm:text-sm"
              placeholder="Password"
            />
          </div>

          <button
            type="submit"
            disabled={loading}
            className="group relative w-full flex justify-center py-2 px-4 border border-transparent text-sm font-medium rounded-md text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 disabled:opacity-50"
          >
            {loading ? 'Loading...' : (mode === 'signin' ? 'Sign in' : 'Sign up')}
          </button>
          
          <div className="text-center">
            <button
              type="button"
              onClick={() => setMode(mode === 'signin' ? 'signup' : 'signin')}
              className="text-indigo-600 hover:text-indigo-500"
            >
              {mode === 'signin' ? "Need an account? Sign up" : 'Have an account? Sign in'}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}
JSX

auth_file.update!(content: auth_content)
puts "✅ Created Auth.jsx"

# Step 2: Update App.tsx with authentication
puts "\n2. Updating App.tsx..."
app_tsx = app.app_files.find_by(path: 'src/App.tsx')
if app_tsx
  new_app_content = <<~TSX
import React, { useState, useEffect } from 'react'
import { supabase } from './lib/supabase'
import { analytics } from './lib/analytics'
import { Auth } from './components/Auth'
import { PlusIcon, TrashIcon, CheckIcon } from '@heroicons/react/24/outline'

interface Todo {
  id: string
  text: string
  completed: boolean
  created_at: string
  user_id?: string
}

function App() {
  const [user, setUser] = useState<any>(null)
  const [todos, setTodos] = useState<Todo[]>([])
  const [newTodo, setNewTodo] = useState('')
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    // Check current session
    supabase.auth.getSession().then(({ data: { session } }) => {
      setUser(session?.user ?? null)
      setLoading(false)
    })

    // Listen for auth changes
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
    try {
      const { data, error } = await supabase
        .from('app_57_todos')
        .select('*')
        .eq('user_id', user.id)
        .order('created_at', { ascending: false })
      
      if (error) throw error
      setTodos(data || [])
    } catch (error) {
      console.error('Error fetching todos:', error)
      analytics.track('error', { type: 'fetch_todos', error: (error as Error).message })
    }
  }

  const addTodo = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!newTodo.trim() || !user) return

    try {
      const { data, error } = await supabase
        .from('app_57_todos')
        .insert([{ 
          text: newTodo.trim(), 
          completed: false,
          user_id: user.id
        }])
        .select()
        .single()
      
      if (error) throw error
      setTodos([data, ...todos])
      setNewTodo('')
      analytics.track('todo_added', { text_length: newTodo.trim().length })
    } catch (error) {
      console.error('Error adding todo:', error)
      analytics.track('error', { type: 'add_todo', error: (error as Error).message })
    }
  }

  const toggleTodo = async (id: string, completed: boolean) => {
    if (!user) return
    
    try {
      const { error } = await supabase
        .from('app_57_todos')
        .update({ completed: !completed })
        .eq('id', id)
        .eq('user_id', user.id)
      
      if (error) throw error
      setTodos(todos.map(todo => 
        todo.id === id ? { ...todo, completed: !completed } : todo
      ))
      analytics.track('todo_toggled', { completed: !completed })
    } catch (error) {
      console.error('Error toggling todo:', error)
      analytics.track('error', { type: 'toggle_todo', error: (error as Error).message })
    }
  }

  const deleteTodo = async (id: string) => {
    if (!user) return
    
    try {
      const { error } = await supabase
        .from('app_57_todos')
        .delete()
        .eq('id', id)
        .eq('user_id', user.id)
      
      if (error) throw error
      setTodos(todos.filter(todo => todo.id !== id))
      analytics.track('todo_deleted')
    } catch (error) {
      console.error('Error deleting todo:', error)
      analytics.track('error', { type: 'delete_todo', error: (error as Error).message })
    }
  }

  if (loading) {
    return (
      <div className="min-h-screen bg-gray-50 flex items-center justify-center">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600"></div>
      </div>
    )
  }

  if (!user) {
    return <Auth onAuth={setUser} />
  }

  return (
    <div className="min-h-screen bg-gray-50 py-8">
      <div className="max-w-md mx-auto bg-white rounded-lg shadow-lg overflow-hidden">
        <div className="bg-blue-600 px-6 py-4 flex justify-between items-center">
          <div>
            <h1 className="text-2xl font-bold text-white">TaskFlow</h1>
            <p className="text-blue-100 text-sm">Personal todo management</p>
          </div>
          <button
            onClick={() => supabase.auth.signOut()}
            className="text-white hover:text-blue-200 text-sm"
          >
            Sign Out
          </button>
        </div>
        
        <div className="p-6">
          <form onSubmit={addTodo} className="mb-6">
            <div className="flex gap-2">
              <input
                type="text"
                value={newTodo}
                onChange={(e) => setNewTodo(e.target.value)}
                placeholder="Add a new task..."
                className="flex-1 px-4 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              />
              <button
                type="submit"
                className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 transition-colors"
              >
                <PlusIcon className="h-5 w-5" />
              </button>
            </div>
          </form>

          <div className="space-y-2">
            {todos.length === 0 ? (
              <div className="text-center py-8 text-gray-500">
                <p>No tasks yet. Add one above!</p>
              </div>
            ) : (
              todos.map((todo) => (
                <div
                  key={todo.id}
                  className="flex items-center gap-3 p-3 border border-gray-200 rounded-lg hover:bg-gray-50 transition-colors"
                >
                  <button
                    onClick={() => toggleTodo(todo.id, todo.completed)}
                    className={\`flex-shrink-0 w-5 h-5 rounded border-2 flex items-center justify-center transition-colors \${
                      todo.completed
                        ? 'bg-green-500 border-green-500 text-white'
                        : 'border-gray-300 hover:border-green-400'
                    }\`}
                  >
                    {todo.completed && <CheckIcon className="h-3 w-3" />}
                  </button>
                  
                  <span
                    className={\`flex-1 \${
                      todo.completed
                        ? 'text-gray-500 line-through'
                        : 'text-gray-900'
                    }\`}
                  >
                    {todo.text}
                  </span>
                  
                  <button
                    onClick={() => deleteTodo(todo.id)}
                    className="flex-shrink-0 p-1 text-red-500 hover:text-red-700 hover:bg-red-50 rounded transition-colors"
                  >
                    <TrashIcon className="h-4 w-4" />
                  </button>
                </div>
              ))
            )}
          </div>

          {todos.length > 0 && (
            <div className="mt-6 text-sm text-gray-500 text-center">
              {todos.filter(t => !t.completed).length} of {todos.length} tasks remaining
            </div>
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

# Step 3: Update app status
app.update!(status: 'generated')
puts "\n3. App status updated to: #{app.status}"

# Step 4: Deploy the app
puts "\n4. Deploying to Cloudflare..."
begin
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
end

# Step 5: Output table creation SQL
puts "\n" + "=" * 60
puts "IMPORTANT: Create this table in Supabase SQL Editor"
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
CREATE POLICY "Users can view own todos"
  ON app_57_todos FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own todos"
  ON app_57_todos FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own todos"
  ON app_57_todos FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own todos"
  ON app_57_todos FOR DELETE
  USING (auth.uid() = user_id);

-- Permissions
GRANT ALL ON app_57_todos TO authenticated;
GRANT ALL ON app_57_todos TO service_role;
SQL

puts sql

# Save SQL to file
sql_file = Rails.root.join('tmp', "app_57_create_todos_table.sql")
File.write(sql_file, sql)
puts "\n✅ SQL saved to: #{sql_file}"

puts "\n" + "=" * 60
puts "REGENERATION COMPLETE"
puts "=" * 60
puts "App: #{app.name}"
puts "Status: #{app.status}"
puts "URL: #{app.preview_url || 'https://preview-57.overskill.app'}"
puts "\nNext Steps:"
puts "1. Copy the SQL above"
puts "2. Go to Supabase SQL Editor"
puts "3. Execute the SQL to create the table"
puts "4. Test authentication at the preview URL"
puts "=" * 60