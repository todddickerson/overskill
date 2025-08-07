# Complete Database Architecture Plan for OverSkill

## Executive Summary

We have a sophisticated multi-tenant database architecture using Supabase sharding (10,000 apps per shard) but need to connect it with automatic table creation, user authentication, and AI-aware generation.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    OverSkill Rails App                   │
├─────────────────────────────────────────────────────────┤
│  DatabaseShard (Manages multiple Supabase projects)      │
│  ├── Shard 001: Apps 1-10,000                           │
│  ├── Shard 002: Apps 10,001-20,000                      │
│  └── Shard 003: Apps 20,001-30,000                      │
└─────────────────────────────────────────────────────────┘
                             ↓
┌─────────────────────────────────────────────────────────┐
│              Supabase Project (Per Shard)                │
├─────────────────────────────────────────────────────────┤
│  Tables (with app_id prefix for isolation):              │
│  ├── app_57_todos    (user_id, text, completed)         │
│  ├── app_57_users    (profile data)                     │
│  ├── app_128_posts   (user_id, title, content)         │
│  └── app_234_notes   (user_id, content)                 │
│                                                          │
│  RLS Policies:                                          │
│  ├── User can only see their own data                   │
│  └── App isolation via table prefixes                   │
└─────────────────────────────────────────────────────────┘
```

## Implementation Plan

### Phase 1: Connect Sharding to Table Creation (Immediate)

#### 1.1 Fix App-DatabaseShard Association

```ruby
# app/models/app.rb
class App < ApplicationRecord
  belongs_to :database_shard, optional: true
  
  # Automatically assign to shard on creation
  before_create :assign_to_shard
  
  private
  
  def assign_to_shard
    self.database_shard ||= DatabaseShard.current_shard
  end
  
  # Get Supabase credentials from shard
  def supabase_url
    database_shard&.supabase_url
  end
  
  def supabase_anon_key
    database_shard&.supabase_anon_key
  end
  
  def supabase_service_key
    database_shard&.supabase_service_key
  end
end
```

#### 1.2 Enhanced Table Creation Service

```ruby
# app/services/database/table_creator_service.rb
class Database::TableCreatorService
  def initialize(app)
    @app = app
    @shard = app.database_shard
    raise "App not assigned to database shard" unless @shard
  end
  
  def create_table_for_entity!(entity)
    table_name = "app_#{@app.id}_#{entity.name}"
    
    sql = build_create_table_sql(table_name, entity)
    rls_sql = build_rls_policies_sql(table_name, entity)
    
    # Execute on the app's shard
    client = @shard.supabase_client(use_service_key: true)
    
    # Create table
    client.rpc('exec_sql', { sql: sql })
    
    # Apply RLS policies
    client.rpc('exec_sql', { sql: rls_sql }) if entity.user_scoped?
    
    Rails.logger.info "[TableCreator] Created #{table_name} on #{@shard.name}"
    
    true
  rescue => e
    Rails.logger.error "[TableCreator] Failed to create #{table_name}: #{e.message}"
    false
  end
  
  private
  
  def build_create_table_sql(table_name, entity)
    columns = []
    
    # Standard columns
    columns << "id UUID DEFAULT gen_random_uuid() PRIMARY KEY"
    
    # User scoping
    if entity.user_scoped?
      columns << "user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE"
    end
    
    # Entity-specific columns
    entity.app_table_columns.each do |col|
      columns << column_definition(col)
    end
    
    # Timestamps
    columns << "created_at TIMESTAMPTZ DEFAULT NOW()"
    columns << "updated_at TIMESTAMPTZ DEFAULT NOW()"
    
    <<~SQL
      CREATE TABLE IF NOT EXISTS #{table_name} (
        #{columns.join(",\n        ")}
      );
      
      -- Indexes for performance
      CREATE INDEX IF NOT EXISTS idx_#{table_name}_user_id ON #{table_name}(user_id);
      CREATE INDEX IF NOT EXISTS idx_#{table_name}_created_at ON #{table_name}(created_at DESC);
    SQL
  end
  
  def build_rls_policies_sql(table_name, entity)
    <<~SQL
      -- Enable RLS
      ALTER TABLE #{table_name} ENABLE ROW LEVEL SECURITY;
      
      -- Users can only see their own data
      CREATE POLICY "Users can view own #{entity.name}"
        ON #{table_name} FOR SELECT
        USING (auth.uid() = user_id);
      
      -- Users can only insert their own data
      CREATE POLICY "Users can insert own #{entity.name}"
        ON #{table_name} FOR INSERT
        WITH CHECK (auth.uid() = user_id);
      
      -- Users can only update their own data
      CREATE POLICY "Users can update own #{entity.name}"
        ON #{table_name} FOR UPDATE
        USING (auth.uid() = user_id)
        WITH CHECK (auth.uid() = user_id);
      
      -- Users can only delete their own data
      CREATE POLICY "Users can delete own #{entity.name}"
        ON #{table_name} FOR DELETE
        USING (auth.uid() = user_id);
    SQL
  end
  
  def column_definition(col)
    sql_type = case col.column_type
    when 'text' then 'TEXT'
    when 'number' then 'NUMERIC'
    when 'boolean' then 'BOOLEAN'
    when 'date' then 'DATE'
    when 'datetime', 'timestamp' then 'TIMESTAMPTZ'
    when 'uuid' then 'UUID'
    when 'json' then 'JSONB'
    else 'TEXT'
    end
    
    definition = "#{col.name} #{sql_type}"
    definition += " NOT NULL" if col.is_required?
    definition += " DEFAULT #{col.default_value}" if col.default_value.present?
    
    definition
  end
end
```

### Phase 2: Quick Fix for App 57 (Today)

```ruby
# Fix script to run immediately
# bin/rails runner scripts/fix_app_57_database.rb

app = App.find(57)

# Ensure app has a database shard
unless app.database_shard
  app.database_shard = DatabaseShard.current_shard
  app.save!
end

# Create todos table entity
todos_table = app.app_tables.find_or_create_by!(name: 'todos') do |t|
  t.team = app.team
  t.display_name = 'Todos'
  t.scope_type = :user_scoped
end

# Define columns if not exists
if todos_table.app_table_columns.empty?
  todos_table.app_table_columns.create!([
    { name: 'text', column_type: 'text', is_required: true },
    { name: 'completed', column_type: 'boolean', default_value: 'false' }
  ])
end

# Create table in Supabase
service = Database::TableCreatorService.new(app)
if service.create_table_for_entity!(todos_table)
  puts "✅ Created todos table for App 57"
  
  # Update deployment to use correct Supabase credentials
  deploy_service = Deployment::CloudflarePreviewService.new(app)
  result = deploy_service.update_preview!
  
  if result[:success]
    puts "✅ Redeployed app with database connection"
    puts "🌐 Preview URL: #{result[:preview_url]}"
  else
    puts "❌ Deployment failed: #{result[:error]}"
  end
else
  puts "❌ Failed to create todos table"
end
```

### Phase 3: Update AI Prompts (Critical)

```markdown
# Updated AI_APP_STANDARDS.md

## CRITICAL: Database Architecture Rules

### Table Naming Convention
ALL database tables MUST use the app ID prefix:
- ✅ CORRECT: `app_57_todos`
- ❌ WRONG: `todos`

### Authentication is MANDATORY for User Data

When generating ANY app with user-specific data:

1. **Import Supabase Auth**:
```javascript
import { supabase } from './lib/supabase'
```

2. **Create Auth Component** (REQUIRED):
```jsx
// src/components/AuthForm.jsx
import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'

export function AuthForm({ onAuth }) {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [loading, setLoading] = useState(false)
  const [mode, setMode] = useState('signin') // 'signin' or 'signup'

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
      <div className="max-w-md w-full space-y-8">
        <div>
          <h2 className="mt-6 text-center text-3xl font-extrabold text-gray-900">
            {mode === 'signin' ? 'Sign in to your account' : 'Create new account'}
          </h2>
        </div>
        <form className="mt-8 space-y-6" onSubmit={handleSubmit}>
          <div className="rounded-md shadow-sm -space-y-px">
            <input
              type="email"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="appearance-none rounded-none relative block w-full px-3 py-2 border border-gray-300 placeholder-gray-500 text-gray-900 rounded-t-md focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 focus:z-10 sm:text-sm"
              placeholder="Email address"
            />
            <input
              type="password"
              required
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="appearance-none rounded-none relative block w-full px-3 py-2 border border-gray-300 placeholder-gray-500 text-gray-900 rounded-b-md focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 focus:z-10 sm:text-sm"
              placeholder="Password"
            />
          </div>

          <div>
            <button
              type="submit"
              disabled={loading}
              className="group relative w-full flex justify-center py-2 px-4 border border-transparent text-sm font-medium rounded-md text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
            >
              {loading ? 'Loading...' : (mode === 'signin' ? 'Sign in' : 'Sign up')}
            </button>
          </div>
          
          <div className="text-center">
            <button
              type="button"
              onClick={() => setMode(mode === 'signin' ? 'signup' : 'signin')}
              className="text-indigo-600 hover:text-indigo-500"
            >
              {mode === 'signin' ? "Don't have an account? Sign up" : 'Already have an account? Sign in'}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}
```

3. **Main App MUST Check Authentication**:
```jsx
// src/App.jsx
import { useState, useEffect } from 'react'
import { supabase } from './lib/supabase'
import { AuthForm } from './components/AuthForm'

function App() {
  const [user, setUser] = useState(null)
  const [loading, setLoading] = useState(true)
  const [todos, setTodos] = useState([])

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
      fetchUserTodos()
    }
  }, [user])

  const fetchUserTodos = async () => {
    // CRITICAL: Use full table name with app ID prefix
    const { data, error } = await supabase
      .from(`app_${window.ENV.APP_ID}_todos`)
      .select('*')
      .eq('user_id', user.id)
      .order('created_at', { ascending: false })
    
    if (!error) setTodos(data)
  }

  if (loading) return <div>Loading...</div>
  
  if (!user) {
    return <AuthForm onAuth={setUser} />
  }

  return (
    <div className="app">
      <header>
        <h1>My App</h1>
        <button onClick={() => supabase.auth.signOut()}>Sign Out</button>
      </header>
      {/* Rest of app */}
    </div>
  )
}
```

4. **ALL Database Operations MUST Include user_id**:
```javascript
// ✅ CORRECT: Include user_id when creating
const { data, error } = await supabase
  .from(`app_${window.ENV.APP_ID}_todos`)
  .insert([{
    text: newTodo,
    user_id: user.id,  // REQUIRED
    completed: false
  }])

// ✅ CORRECT: Filter by user_id when fetching
const { data } = await supabase
  .from(`app_${window.ENV.APP_ID}_todos`)
  .select('*')
  .eq('user_id', user.id)  // REQUIRED
```

### NEVER Generate Apps Without Authentication

If the app involves ANY user data (todos, notes, posts, etc.), you MUST:
1. Include AuthForm component
2. Check authentication in App.jsx
3. Include user_id in all database operations
4. Use the full table name with app_${APP_ID}_ prefix
```

### Phase 4: Admin Dashboard UI

```erb
<!-- app/views/account/apps/_database_tab.html.erb -->
<div class="database-dashboard">
  <div class="database-header">
    <h3>Database Configuration</h3>
    <div class="shard-info">
      <span class="label">Shard:</span>
      <span class="value"><%= @app.database_shard&.name || 'Not assigned' %></span>
      <% if @app.database_shard %>
        <span class="badge <%= @app.database_shard.status %>">
          <%= @app.database_shard.status.humanize %>
        </span>
      <% end %>
    </div>
  </div>

  <div class="tables-section">
    <div class="section-header">
      <h4>Database Tables</h4>
      <%= link_to "+ Create Table", new_account_app_app_table_path(@app), 
          class: "btn btn-sm btn-primary", 
          data: { turbo_frame: "modal" } %>
    </div>

    <div class="tables-grid">
      <% @app.app_tables.each do |table| %>
        <div class="table-card">
          <div class="table-header">
            <h5><%= table.display_name %></h5>
            <code>app_<%= @app.id %>_<%= table.name %></code>
          </div>
          
          <div class="table-info">
            <div class="info-row">
              <span>Scope:</span>
              <span class="badge <%= table.scope_type %>">
                <%= table.scope_type.humanize %>
              </span>
            </div>
            
            <% if table.user_scoped? %>
              <div class="security-info">
                <i class="icon-shield"></i>
                User authentication required
                <br>
                <i class="icon-lock"></i>
                Row-level security enabled
              </div>
            <% end %>
            
            <div class="columns-preview">
              <strong>Columns:</strong>
              <%= table.app_table_columns.limit(3).pluck(:name).join(', ') %>
              <% if table.app_table_columns.count > 3 %>
                ... and <%= table.app_table_columns.count - 3 %> more
              <% end %>
            </div>
          </div>
          
          <div class="table-actions">
            <%= link_to "Edit Schema", 
                edit_account_app_app_table_path(@app, table),
                class: "btn btn-sm" %>
            
            <% if table.created_in_supabase? %>
              <%= link_to "View Data", 
                  account_app_app_table_records_path(@app, table),
                  class: "btn btn-sm" %>
            <% else %>
              <%= button_to "Create in Database", 
                  create_in_supabase_account_app_app_table_path(@app, table),
                  method: :post,
                  class: "btn btn-sm btn-success" %>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
  </div>

  <div class="auth-section">
    <h4>Authentication Status</h4>
    <div class="auth-info">
      <% if @app.database_shard %>
        <div class="info-row">
          <span>Supabase Auth:</span>
          <span class="badge success">Configured</span>
        </div>
        <div class="info-row">
          <span>Auth URL:</span>
          <code><%= @app.database_shard.supabase_url %>/auth/v1</code>
        </div>
        <p class="help-text">
          Users can sign up and log in to your app using email/password authentication.
        </p>
      <% else %>
        <div class="alert alert-warning">
          Database shard not assigned. Authentication unavailable.
        </div>
      <% end %>
    </div>
  </div>
</div>
```

## Benefits of This Architecture

1. **Cost Efficiency**: 10,000 apps share each Supabase project
2. **Perfect Isolation**: RLS policies + table prefixes ensure data separation
3. **Automatic Scaling**: New shards created as needed
4. **User Authentication**: Built-in Supabase Auth per shard
5. **Simple for Developers**: AI handles all complexity

## Immediate Action Items

1. **Run fix script for App 57** to create todos table
2. **Update AI prompts** to include authentication
3. **Test full flow**: Generate app → Auth → Create todo → View todo
4. **Add database tab** to app dashboard UI

This architecture gives us enterprise-grade multi-tenancy with user authentication at a fraction of the cost of individual Supabase projects per app.