# App Database Entity System - Implementation Plan

## Overview

We need to automatically create and manage database tables for generated apps with proper user authentication and data scoping. This document outlines the complete solution.

## Current State

### What We Have ✅
- **AppTable & AppTableColumn models**: Database schema management
- **Supabase integration**: Connection and API client
- **Vite build system**: Working React app deployment
- **Environment variables**: Supabase credentials injected into apps

### What's Missing ❌
- **Automatic table creation**: Tables don't exist in Supabase
- **User authentication**: No login system in generated apps
- **Data scoping**: No user_id foreign keys or RLS policies
- **AI awareness**: AI doesn't generate auth or user-scoped queries

## Solution Architecture

### 1. Automatic Table Creation on App Generation

```ruby
# app/services/database/app_schema_service.rb
class Database::AppSchemaService
  def initialize(app)
    @app = app
    @supabase = Supabase::AppDatabaseService.new(app)
  end
  
  def setup_default_schema!
    # Create default tables based on app type
    case @app.app_type
    when 'tool'
      create_todo_schema! if @app.name.downcase.include?('todo')
      create_note_schema! if @app.name.downcase.include?('note')
    when 'saas'
      create_user_profile_schema!
      create_subscription_schema!
    end
  end
  
  private
  
  def create_todo_schema!
    # Create todos table with user scoping
    table = @app.app_tables.create!(
      name: 'todos',
      display_name: 'Todos',
      user_scoped: true,
      auth_required: true
    )
    
    # Add columns
    table.app_table_columns.create!([
      { name: 'id', column_type: 'uuid', is_primary: true },
      { name: 'user_id', column_type: 'uuid', is_foreign_key: true, foreign_table: 'auth.users' },
      { name: 'text', column_type: 'text', is_required: true },
      { name: 'completed', column_type: 'boolean', default_value: 'false' },
      { name: 'created_at', column_type: 'timestamp', default_value: 'now()' },
      { name: 'updated_at', column_type: 'timestamp', default_value: 'now()' }
    ])
    
    # Create in Supabase with RLS
    create_supabase_table_with_rls!(table)
  end
  
  def create_supabase_table_with_rls!(table)
    sql = generate_create_table_sql(table)
    rls_sql = generate_rls_policies(table)
    
    @supabase.execute_sql(sql)
    @supabase.execute_sql(rls_sql)
  end
  
  def generate_create_table_sql(table)
    <<~SQL
      CREATE TABLE IF NOT EXISTS app_#{@app.id}_#{table.name} (
        #{table.app_table_columns.map { |col| column_definition(col) }.join(",\n        ")}
      );
    SQL
  end
  
  def generate_rls_policies(table)
    return '' unless table.user_scoped?
    
    <<~SQL
      ALTER TABLE app_#{@app.id}_#{table.name} ENABLE ROW LEVEL SECURITY;
      
      CREATE POLICY "Users can view own #{table.name}"
        ON app_#{@app.id}_#{table.name} FOR SELECT
        USING (auth.uid() = user_id);
        
      CREATE POLICY "Users can insert own #{table.name}"
        ON app_#{@app.id}_#{table.name} FOR INSERT
        WITH CHECK (auth.uid() = user_id);
        
      CREATE POLICY "Users can update own #{table.name}"
        ON app_#{@app.id}_#{table.name} FOR UPDATE
        USING (auth.uid() = user_id);
        
      CREATE POLICY "Users can delete own #{table.name}"
        ON app_#{@app.id}_#{table.name} FOR DELETE
        USING (auth.uid() = user_id);
    SQL
  end
end
```

### 2. Enhanced AppTable Model

```ruby
# app/models/app_table.rb
class AppTable < ApplicationRecord
  belongs_to :app
  belongs_to :team
  has_many :app_table_columns, dependent: :destroy
  
  # Scoping types
  enum :scope_type, {
    public: 0,      # No authentication needed
    user_scoped: 1, # Each user owns their data
    team_scoped: 2, # Shared within team
    app_scoped: 3   # Global for app
  }, default: :user_scoped
  
  validates :name, presence: true, 
    format: { with: /\A[a-z][a-z0-9_]*\z/, message: "must be lowercase with underscores" }
  
  def supabase_table_name
    "app_#{app_id}_#{name}"
  end
  
  def requires_auth?
    !public?
  end
  
  def has_user_id_column?
    user_scoped? || team_scoped?
  end
  
  # Generate TypeScript interface for the table
  def to_typescript_interface
    <<~TS
      interface #{name.camelize.singularize} {
        #{app_table_columns.map(&:to_typescript).join("\n        ")}
      }
    TS
  end
  
  # Generate Supabase query examples
  def generate_query_examples
    if user_scoped?
      <<~JS
        // Fetch user's #{name}
        const { data } = await supabase
          .from('#{supabase_table_name}')
          .select('*')
          .eq('user_id', user.id)
          .order('created_at', { ascending: false })
        
        // Create new #{name.singularize}
        const { data, error } = await supabase
          .from('#{supabase_table_name}')
          .insert([{ 
            ...formData,
            user_id: user.id // Required for user-scoped tables
          }])
      JS
    else
      <<~JS
        // Fetch all #{name}
        const { data } = await supabase
          .from('#{supabase_table_name}')
          .select('*')
          .order('created_at', { ascending: false })
      JS
    end
  end
end
```

### 3. Admin Dashboard UI Updates

```erb
<!-- app/views/account/app_tables/index.html.erb -->
<div class="app-tables-dashboard">
  <div class="header">
    <h2>Database Tables for <%= @app.name %></h2>
    <%= link_to "+ Create Table", new_account_app_app_table_path(@app), 
        class: "btn btn-primary", data: { turbo_frame: "modal" } %>
  </div>
  
  <div class="tables-grid">
    <% @app.app_tables.each do |table| %>
      <div class="table-card">
        <div class="table-header">
          <h3><%= table.display_name || table.name.humanize %></h3>
          <span class="badge <%= table.scope_type %>">
            <%= table.scope_type.humanize %>
          </span>
        </div>
        
        <div class="table-info">
          <p>Table: <code><%= table.supabase_table_name %></code></p>
          <p>Columns: <%= table.app_table_columns.count %></p>
          
          <% if table.user_scoped? %>
            <div class="scope-info">
              <i class="icon-lock"></i>
              User authentication required
              <br>
              <i class="icon-user"></i>
              Each user sees only their data
            </div>
          <% end %>
        </div>
        
        <div class="table-actions">
          <%= link_to "Manage Schema", 
              account_app_app_table_path(@app, table),
              class: "btn btn-sm" %>
          <%= link_to "View Data", 
              account_app_app_table_records_path(@app, table),
              class: "btn btn-sm" %>
          <%= button_to "Create in Supabase", 
              create_in_supabase_account_app_app_table_path(@app, table),
              method: :post,
              class: "btn btn-sm btn-success",
              data: { confirm: "Create table in Supabase?" } %>
        </div>
      </div>
    <% end %>
  </div>
</div>
```

### 4. Updated AI Prompts

```markdown
# AI_APP_STANDARDS.md additions

## Database-Aware App Generation

### CRITICAL: Authentication Required for User Data

When generating apps with user-specific data (todos, notes, posts, etc.):

1. **ALWAYS include authentication components**:
```jsx
// src/components/Auth.jsx
import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'

export function Auth({ onAuth }) {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [isSignUp, setIsSignUp] = useState(false)
  const [loading, setLoading] = useState(false)
  const [user, setUser] = useState(null)

  useEffect(() => {
    // Check for existing session
    supabase.auth.getSession().then(({ data: { session } }) => {
      if (session?.user) {
        setUser(session.user)
        onAuth(session.user)
      }
    })

    // Listen for auth changes
    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
      const currentUser = session?.user ?? null
      setUser(currentUser)
      onAuth(currentUser)
    })

    return () => subscription.unsubscribe()
  }, [onAuth])

  const handleAuth = async (e) => {
    e.preventDefault()
    setLoading(true)
    
    const { data, error } = isSignUp
      ? await supabase.auth.signUp({ email, password })
      : await supabase.auth.signInWithPassword({ email, password })
    
    if (error) {
      alert(error.message)
    } else if (data.user) {
      onAuth(data.user)
    }
    
    setLoading(false)
  }

  if (user) {
    return (
      <div className="auth-status">
        <span>Logged in as {user.email}</span>
        <button onClick={() => supabase.auth.signOut()}>Sign Out</button>
      </div>
    )
  }

  return (
    <form onSubmit={handleAuth} className="auth-form">
      <h2>{isSignUp ? 'Sign Up' : 'Sign In'}</h2>
      <input
        type="email"
        placeholder="Email"
        value={email}
        onChange={(e) => setEmail(e.target.value)}
        required
      />
      <input
        type="password"
        placeholder="Password"
        value={password}
        onChange={(e) => setPassword(e.target.value)}
        required
      />
      <button type="submit" disabled={loading}>
        {loading ? 'Loading...' : (isSignUp ? 'Sign Up' : 'Sign In')}
      </button>
      <button type="button" onClick={() => setIsSignUp(!isSignUp)}>
        {isSignUp ? 'Already have an account? Sign In' : 'Need an account? Sign Up'}
      </button>
    </form>
  )
}
```

2. **ALWAYS scope database queries to the authenticated user**:
```jsx
// CORRECT: User-scoped query
const fetchTodos = async (userId) => {
  const { data, error } = await supabase
    .from('app_57_todos')  // Use full table name
    .select('*')
    .eq('user_id', userId)  // CRITICAL: Filter by user
    .order('created_at', { ascending: false })
  
  if (error) {
    console.error('Error fetching todos:', error)
    return []
  }
  return data
}

// CORRECT: Insert with user_id
const createTodo = async (text, userId) => {
  const { data, error } = await supabase
    .from('app_57_todos')
    .insert([{
      text,
      user_id: userId,  // CRITICAL: Set ownership
      completed: false
    }])
    .select()
    .single()
  
  return { data, error }
}
```

3. **Main App component pattern with authentication**:
```jsx
function App() {
  const [user, setUser] = useState(null)
  const [todos, setTodos] = useState([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    if (user) {
      fetchTodos(user.id).then(setTodos)
    }
    setLoading(false)
  }, [user])

  if (loading) {
    return <div>Loading...</div>
  }

  if (!user) {
    return <Auth onAuth={setUser} />
  }

  return (
    <div className="app">
      <header>
        <h1>My Todos</h1>
        <button onClick={() => supabase.auth.signOut()}>Sign Out</button>
      </header>
      <TodoList todos={todos} userId={user.id} onUpdate={setTodos} />
    </div>
  )
}
```

### Table Naming Convention

ALWAYS use the full table name with app ID prefix:
- ✅ CORRECT: `app_57_todos`
- ❌ WRONG: `todos`

This ensures proper multi-tenant isolation.
```

### 5. Automatic Table Creation Hook

```ruby
# app/jobs/create_app_database_job.rb
class CreateAppDatabaseJob < ApplicationJob
  def perform(app_id)
    app = App.find(app_id)
    
    # Analyze app files to detect needed tables
    detector = Database::SchemaDetectorService.new(app)
    detected_tables = detector.analyze_code_for_tables
    
    # Create tables in our database
    detected_tables.each do |table_name|
      next if app.app_tables.exists?(name: table_name)
      
      table = app.app_tables.create!(
        name: table_name,
        display_name: table_name.humanize,
        scope_type: :user_scoped,
        auth_required: true
      )
      
      # Add standard columns
      add_standard_columns(table)
    end
    
    # Create all tables in Supabase
    schema_service = Database::AppSchemaService.new(app)
    schema_service.create_all_tables_in_supabase!
    
    # Broadcast completion
    broadcast_database_ready(app)
  end
  
  private
  
  def add_standard_columns(table)
    columns = [
      { name: 'id', column_type: 'uuid', is_primary: true },
      { name: 'created_at', column_type: 'timestamp', default_value: 'now()' },
      { name: 'updated_at', column_type: 'timestamp', default_value: 'now()' }
    ]
    
    if table.user_scoped?
      columns << { name: 'user_id', column_type: 'uuid', is_foreign_key: true }
    end
    
    # Add table-specific columns based on name
    case table.name
    when 'todos'
      columns += [
        { name: 'text', column_type: 'text', is_required: true },
        { name: 'completed', column_type: 'boolean', default_value: 'false' }
      ]
    when 'notes'
      columns += [
        { name: 'title', column_type: 'text' },
        { name: 'content', column_type: 'text', is_required: true }
      ]
    when 'posts'
      columns += [
        { name: 'title', column_type: 'text', is_required: true },
        { name: 'content', column_type: 'text', is_required: true },
        { name: 'published', column_type: 'boolean', default_value: 'false' }
      ]
    end
    
    table.app_table_columns.create!(columns)
  end
end
```

### 6. Schema Detector Service

```ruby
# app/services/database/schema_detector_service.rb
class Database::SchemaDetectorService
  def initialize(app)
    @app = app
  end
  
  def analyze_code_for_tables
    tables = Set.new
    
    @app.app_files.each do |file|
      next unless file.path.match?(/\.(jsx?|tsx?)$/)
      
      content = file.content
      
      # Look for Supabase .from() calls
      content.scan(/supabase\s*\.\s*from\s*\(\s*['"`](\w+)['"`]\s*\)/).each do |match|
        table_name = match[0]
        # Remove app prefix if present
        table_name = table_name.gsub(/^app_\d+_/, '')
        tables.add(table_name)
      end
      
      # Look for common entity names in variable/function names
      %w[todos notes posts users projects tasks items].each do |entity|
        if content.match?(/#{entity}/i)
          tables.add(entity)
        end
      end
    end
    
    tables.to_a
  end
end
```

## Implementation Steps

### Immediate Actions (Today)

1. **Fix App 57's todos table**:
```ruby
app = App.find(57)

# Create table record
table = app.app_tables.create!(
  name: 'todos',
  display_name: 'Todos',
  scope_type: :user_scoped
)

# Add columns
table.app_table_columns.create!([
  { name: 'id', column_type: 'uuid', is_primary: true },
  { name: 'user_id', column_type: 'uuid', is_foreign_key: true },
  { name: 'text', column_type: 'text', is_required: true },
  { name: 'completed', column_type: 'boolean', default_value: 'false' },
  { name: 'created_at', column_type: 'timestamp', default_value: 'now()' }
])

# Create in Supabase
service = Database::AppSchemaService.new(app)
service.create_supabase_table_with_rls!(table)
```

2. **Update AI prompts** to include authentication components

3. **Add schema detection** to app generation flow

### Next Week

1. **Build admin UI** for table management
2. **Add team scoping** support
3. **Create migration tools** for schema changes

## Benefits

1. **Security**: Automatic RLS policies ensure data isolation
2. **Simplicity**: Developers don't manually create tables
3. **Consistency**: Standard patterns across all apps
4. **Scalability**: Multi-tenant architecture built-in
5. **User Experience**: Apps work immediately after generation

This system ensures every generated app has proper database tables with user authentication and data isolation from day one.