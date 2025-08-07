# Multi-Tenant Database Architecture for OverSkill Apps

## Executive Summary

We need a system where generated apps can:
1. Define their database entities (tables)
2. Support user authentication and login
3. Scope data to users (user owns todos, posts, etc.)
4. Work seamlessly with Supabase Row Level Security (RLS)

## Current State Analysis

### What We Have
- **Supabase Integration**: Basic connection working
- **App Isolation**: Each app gets prefix `app_{id}_tablename`
- **Database Dashboard**: UI for creating tables/columns
- **AI Generation**: Creates React apps with Supabase client

### What's Missing
- **User Authentication**: No login system for generated apps
- **Data Ownership**: No user_id foreign keys or RLS policies
- **Entity Definitions**: No way to specify which tables an app uses
- **AI Awareness**: AI doesn't know about user scoping patterns

## Proposed Architecture

### 1. Entity Definition System

```ruby
# New model: app_entities.rb
class AppEntity < ApplicationRecord
  belongs_to :app
  belongs_to :team
  
  # Core fields
  # - name: "todos", "posts", "projects"
  # - table_name: "app_57_todos"
  # - user_scoped: true/false
  # - auth_required: true/false
  # - schema_definition: JSON column structure
  # - rls_policies: JSON RLS rules
  
  enum :scope_type, {
    public: 'public',        # No authentication needed
    user_scoped: 'user',     # Owned by user_id
    team_scoped: 'team',     # Shared within team
    app_scoped: 'app'        # Global for app
  }
  
  def supabase_table_name
    "app_#{app_id}_#{name}"
  end
  
  def create_in_supabase!
    # Create table with user_id if user_scoped
    # Apply RLS policies based on scope_type
  end
end
```

### 2. Database Schema Patterns

#### User-Scoped Entity (todos, notes, etc.)
```sql
-- Table creation
CREATE TABLE app_57_todos (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id),
  text TEXT NOT NULL,
  completed BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS Policy
ALTER TABLE app_57_todos ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can only see their own todos"
  ON app_57_todos FOR ALL
  USING (auth.uid() = user_id);
```

#### Team-Scoped Entity (projects, documents)
```sql
CREATE TABLE app_57_projects (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  team_id UUID NOT NULL,
  created_by UUID NOT NULL REFERENCES auth.users(id),
  name TEXT NOT NULL,
  -- other fields
);

-- RLS for team members
CREATE POLICY "Team members can see team projects"
  ON app_57_projects FOR SELECT
  USING (
    team_id IN (
      SELECT team_id FROM app_57_team_members 
      WHERE user_id = auth.uid()
    )
  );
```

### 3. Admin Dashboard UI

#### Entity Management Interface
```erb
<!-- app/views/account/app_entities/index.html.erb -->
<div class="entity-manager">
  <h2>Database Entities for <%= @app.name %></h2>
  
  <div class="entity-list">
    <% @app.app_entities.each do |entity| %>
      <div class="entity-card">
        <h3><%= entity.name %></h3>
        
        <div class="entity-settings">
          <label>
            Scope Type: 
            <%= select_tag :scope_type, 
                options_for_select(['public', 'user_scoped', 'team_scoped'], 
                entity.scope_type) %>
          </label>
          
          <% if entity.user_scoped? %>
            <div class="user-scope-config">
              ✅ Requires Authentication
              ✅ Each user sees only their data
              ✅ RLS policies applied
            </div>
          <% end %>
        </div>
        
        <div class="entity-columns">
          <!-- Column definitions -->
        </div>
      </div>
    <% end %>
  </div>
  
  <button class="btn-primary">+ Add Entity</button>
</div>
```

### 4. Authentication System for Generated Apps

#### Supabase Auth Integration
```javascript
// Generated auth service for React apps
// src/lib/auth.js

import { supabase } from './supabase'

export const auth = {
  // Sign up with email
  async signUp(email, password) {
    const { data, error } = await supabase.auth.signUp({
      email,
      password,
    })
    return { user: data?.user, error }
  },

  // Sign in
  async signIn(email, password) {
    const { data, error } = await supabase.auth.signInWithPassword({
      email,
      password,
    })
    return { user: data?.user, session: data?.session, error }
  },

  // Sign out
  async signOut() {
    const { error } = await supabase.auth.signOut()
    return { error }
  },

  // Get current user
  async getCurrentUser() {
    const { data: { user } } = await supabase.auth.getUser()
    return user
  },

  // Listen to auth changes
  onAuthStateChange(callback) {
    return supabase.auth.onAuthStateChange(callback)
  }
}
```

#### Auth Components
```jsx
// Generated LoginForm component
function LoginForm() {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [user, setUser] = useState(null)

  useEffect(() => {
    // Check if user is logged in
    auth.getCurrentUser().then(setUser)
    
    // Listen for auth changes
    const { data: { subscription } } = auth.onAuthStateChange((event, session) => {
      setUser(session?.user ?? null)
    })

    return () => subscription.unsubscribe()
  }, [])

  const handleLogin = async (e) => {
    e.preventDefault()
    const { user, error } = await auth.signIn(email, password)
    if (error) {
      alert(error.message)
    } else {
      setUser(user)
    }
  }

  if (user) {
    return <div>Welcome {user.email}! <button onClick={() => auth.signOut()}>Sign Out</button></div>
  }

  return (
    <form onSubmit={handleLogin}>
      <input 
        type="email" 
        value={email} 
        onChange={(e) => setEmail(e.target.value)}
        placeholder="Email"
        required 
      />
      <input 
        type="password" 
        value={password}
        onChange={(e) => setPassword(e.target.value)}
        placeholder="Password"
        required
      />
      <button type="submit">Sign In</button>
    </form>
  )
}
```

### 5. Updated AI Prompts

#### Enhanced System Prompt
```markdown
## Database-Aware App Generation

When generating apps that use database entities:

### 1. Authentication Setup
If the app requires user-specific data:
- ALWAYS include authentication (login/signup)
- Use Supabase Auth for user management
- Include auth.js service for auth operations
- Add LoginForm component

### 2. Entity Definition
For each database table/entity:
- Specify scope_type: public, user_scoped, team_scoped
- Include user_id foreign key for user_scoped entities
- Add appropriate RLS policies

### 3. Data Operations
For user_scoped entities:
```javascript
// ALWAYS filter by current user
const { data: todos } = await supabase
  .from('todos')
  .select('*')
  .eq('user_id', user.id)  // Critical: user scoping
  .order('created_at', { ascending: false })

// When creating, ALWAYS include user_id
const { data } = await supabase
  .from('todos')
  .insert([
    { 
      text: newTodo,
      user_id: user.id  // Critical: ownership
    }
  ])
```

### 4. Generated Schema
When app needs database tables, generate:
```javascript
// src/lib/schema.js
export const DATABASE_SCHEMA = {
  entities: [
    {
      name: 'todos',
      scope: 'user_scoped',
      auth_required: true,
      columns: [
        { name: 'id', type: 'uuid', primary: true },
        { name: 'user_id', type: 'uuid', foreign_key: 'auth.users' },
        { name: 'text', type: 'text', required: true },
        { name: 'completed', type: 'boolean', default: false },
        { name: 'created_at', type: 'timestamptz', default: 'now()' }
      ],
      rls_policies: [
        {
          name: 'Users can only see their own todos',
          operation: 'ALL',
          check: 'auth.uid() = user_id'
        }
      ]
    }
  ]
}
```
```

### 6. Implementation Plan

#### Phase 1: Entity Management (Week 1)
- [ ] Create AppEntity model and migrations
- [ ] Build entity management UI in dashboard
- [ ] Add scope_type selection (public/user/team)
- [ ] Implement Supabase table creation with RLS

#### Phase 2: Authentication (Week 1-2)
- [ ] Create auth component templates
- [ ] Add Supabase Auth configuration per app
- [ ] Generate login/signup forms automatically
- [ ] Implement user session management

#### Phase 3: AI Integration (Week 2)
- [ ] Update AI prompts with database patterns
- [ ] Add schema.js generation to apps
- [ ] Include auth checks in generated code
- [ ] Test with various app types

#### Phase 4: Advanced Features (Week 3+)
- [ ] Team/organization scoping
- [ ] Role-based access control
- [ ] API key management for apps
- [ ] Data migration tools

## Migration Strategy

### For Existing Apps
1. Analyze current app_files for database usage
2. Auto-detect entities from code
3. Generate AppEntity records
4. Apply RLS policies retroactively

### For New Apps
1. AI generates schema.js with entity definitions
2. System creates AppEntity records
3. Supabase tables created with RLS
4. Auth components included if needed

## Example Scenarios

### 1. Todo App (User-Scoped)
```javascript
// Generated with authentication
const TodoApp = () => {
  const [user, setUser] = useState(null)
  const [todos, setTodos] = useState([])

  useEffect(() => {
    // Check authentication
    auth.getCurrentUser().then(user => {
      if (user) {
        setUser(user)
        fetchUserTodos(user.id)
      }
    })
  }, [])

  const fetchUserTodos = async (userId) => {
    const { data } = await supabase
      .from('todos')
      .select('*')
      .eq('user_id', userId)  // User scoping
    setTodos(data || [])
  }

  if (!user) return <LoginForm onLogin={setUser} />
  
  return <TodoList todos={todos} userId={user.id} />
}
```

### 2. Blog App (Public + User Articles)
```javascript
// Mixed scoping
const BlogApp = () => {
  const [publicPosts, setPublicPosts] = useState([])
  const [myPosts, setMyPosts] = useState([])
  const [user, setUser] = useState(null)

  // Public posts - no auth needed
  const fetchPublicPosts = async () => {
    const { data } = await supabase
      .from('posts')
      .select('*')
      .eq('is_public', true)
    setPublicPosts(data)
  }

  // User's posts - requires auth
  const fetchMyPosts = async (userId) => {
    const { data } = await supabase
      .from('posts')
      .select('*')
      .eq('user_id', userId)
    setMyPosts(data)
  }
}
```

### 3. Team Project Manager (Team-Scoped)
```javascript
// Team-based scoping
const ProjectManager = () => {
  const [user, setUser] = useState(null)
  const [team, setTeam] = useState(null)
  const [projects, setProjects] = useState([])

  const fetchTeamProjects = async (teamId) => {
    const { data } = await supabase
      .from('projects')
      .select('*')
      .eq('team_id', teamId)  // Team scoping
    setProjects(data)
  }
}
```

## Benefits

1. **Security**: Automatic RLS policies ensure data isolation
2. **Scalability**: Multi-tenant architecture scales with users
3. **Simplicity**: Developers don't need to think about security
4. **Flexibility**: Supports various scoping patterns
5. **AI-Ready**: Prompts guide proper implementation

## Next Steps

1. **Immediate**: Create AppEntity model and migration
2. **Short-term**: Build entity management UI
3. **Medium-term**: Update AI prompts with patterns
4. **Long-term**: Advanced team/role features

This architecture provides a solid foundation for multi-tenant SaaS apps with proper data isolation and user authentication.