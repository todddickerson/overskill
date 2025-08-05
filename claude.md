# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## IMPORTANT: Check HANDOFF.md First!
**If a HANDOFF.md file exists in the root directory, read it FIRST for:**
- Current development context and state
- Active TODO items and priorities
- Recent changes and issues
- Next steps

**Update HANDOFF.md as you complete tasks by:**
1. Checking off completed items with [x]
2. Adding notes about implementation decisions
3. Updating the "Current State" section
4. Removing completed items when no longer relevant

## Project Overview

OverSkill is an AI-powered app marketplace platform built with Ruby on Rails (BulletTrain framework). It enables non-technical users to create, deploy, and monetize applications using natural language.

## Key Commands

### Development
```bash
# Initial setup (installs dependencies, creates database)
bin/setup

# Start development server (Rails, Sidekiq, JS/CSS builds)
bin/dev

# Rails console
bin/rails console

# Run database migrations
bin/rails db:migrate
```

### Testing
```bash
# Run all tests
bin/rails test

# Run specific test file
bin/rails test test/models/app_test.rb

# Run system tests
bin/rails test:system

# Run with coverage report
COVERAGE=true bin/rails test
```

### Code Quality
```bash
# Ruby linting and formatting
bundle exec standardrb --fix

# Security scan
bundle exec brakeman

# Find N+1 queries (in development)
# Bullet gem will show warnings in browser/console
```

### BulletTrain Super Scaffolding
```bash
# Generate model directly under Team
rails generate super_scaffold ModelName Team field:type{options}

# Generate nested model (belongs to another model)
rails generate super_scaffold ChildModel ParentModel,Team field:type{options}

# Examples:
rails generate super_scaffold App Team \
  name:text_field{required} \
  prompt:text_area{required} \
  status:options{draft,generating,published,failed}

# Nested example (AppVersion belongs to App belongs to Team):
rails generate super_scaffold AppVersion App,Team \
  version_number:text_field{required} \
  changelog:text_area \
  published_at:date_and_time_field

# Three-level nesting example:
rails generate super_scaffold Comment Post,App,Team \
  content:text_area{required} \
  author:references
```

**IMPORTANT**: Always specify the complete ownership chain from immediate parent to Team:
- `ModelName Team` - Direct child of Team
- `ChildModel ParentModel,Team` - Child → Parent → Team  
- `GrandChild Parent,GrandParent,Team` - Three levels deep

## Architecture

### Tech Stack
- **Framework**: Rails 8.0 with BulletTrain Pro 1.26.0
- **Database**: PostgreSQL 14+ (single database, multi-tenant via teams)
- **Background Jobs**: Sidekiq with Redis
- **Frontend**: Hotwire (Turbo + Stimulus), Tailwind CSS
- **AI Integration**: OpenRouter API (Kimi K2 primary)
- **Deployment**: Cloudflare Workers + R2 for generated apps

### Directory Structure
```
app/
├── controllers/
│   ├── account/         # Team-scoped controllers (BulletTrain pattern)
│   │   ├── apps_controller.rb         # CRUD operations for apps
│   │   ├── app_editors_controller.rb  # Code editor interface (/apps/:id/editor)
│   │   ├── app_previews_controller.rb # Preview iframe & file serving (/apps/:id/preview)
│   │   └── app_chats_controller.rb    # Chat interface for AI assistance
│   ├── api/v1/         # API endpoints with JWT auth
│   └── public/         # Public-facing pages
├── models/             # All models belong to teams for multi-tenancy
├── services/           # Business logic (AI generation, deployment, etc.)
│   ├── ai/            # AI integration services
│   ├── deployment/    # App deployment to Cloudflare
│   └── marketplace/   # Commerce and viral mechanics
├── jobs/              # Background jobs (Sidekiq)
└── views/             # ERB templates with Hotwire
```

### Key Controllers

- **Account::AppsController** - Standard CRUD for apps (index, show, new, create, edit, update, destroy)
- **Account::AppEditorsController** - Main editor interface at `/account/apps/:id/editor`
  - Shows chat panel, file tree, code editor, and preview
  - Handles file updates and chat messages
- **Account::AppPreviewsController** - Serves app preview at `/account/apps/:id/preview`
  - `show` action serves the main HTML with asset path rewriting
  - `serve_file` action serves individual JS/CSS files with proper MIME types
- **Account::AppChatsController** - Chat-specific actions (may be merged into editors)

### UI/UX Architecture

#### Namespace Strategy
- **`/account/`** - BulletTrain's default admin namespace (Devise protected)
  - Full CRUD interfaces from super-scaffolding
  - Team management and settings
  - Admin-style views for all models
  - Developer/admin access during development
  
- **`/public/`** - Public-facing dynamic UI
  - Modern marketplace experience
  - AI app generation interface
  - Community features
  - No authentication required for browsing

- **Hybrid Views** - Dynamic based on authentication
  - Marketplace feed visible to all
  - Dynamic navigation (sign in/dashboard)
  - Progressive disclosure of features
  - Same routes, different UI based on auth state

#### Development Strategy
```ruby
# Use super-scaffolding for any model that needs:
# - CRUD operations
# - API endpoints
# - Admin interface
rails generate super_scaffold ModelName Team field:type{options}

# Public controllers for user-facing features
class Public::MarketplaceController < Public::ApplicationController
  def index
    @apps = App.published.featured
    # Dynamic view based on user_signed_in?
  end
end

# Account controllers for admin/management
class Account::AppsController < Account::ApplicationController
  # Full CRUD from super-scaffolding
  # Only accessible to logged-in users
end
```

### Key Patterns

#### BulletTrain Multi-tenancy
```ruby
# All controllers inherit from account-scoped base
class Account::AppsController < Account::ApplicationController
  # current_team and current_user are available
  def index
    @apps = current_team.apps.published
  end
end

# Models belong to teams
class App < ApplicationRecord
  belongs_to :team
  include Records::Base  # BulletTrain concern
end
```

#### Service Objects
```ruby
# Complex operations use service objects
class AI::AppGeneratorService
  def initialize(team)
    @team = team
  end
  
  def generate(prompt, options = {})
    # 1. Validate and enhance prompt
    # 2. Call AI API
    # 3. Security scan results
    # 4. Create records
    # 5. Queue deployment job
  end
end
```

#### Background Jobs
```ruby
# Long-running tasks use Sidekiq
class AppGenerationJob < ApplicationJob
  queue_as :ai_generation
  
  def perform(app)
    # Generate app code via AI
    # Deploy if successful
  end
end
```

## Environment Setup

Required environment variables (copy `.env.example` to `.env`):
- `OPENROUTER_API_KEY` - AI generation
- `STRIPE_API_KEY` + `STRIPE_SECRET_KEY` - Payments (BulletTrain configured)
- `CLOUDFLARE_*` - App hosting
- `SUPABASE_*` - App data storage
- `REDIS_URL` - Background jobs

## Common Development Tasks

### Adding New Features
1. Use BulletTrain's super scaffolding for CRUD operations
2. Create service objects for complex logic
3. Add background jobs for slow operations
4. Follow existing patterns in codebase

### Database Operations
- Migrations: `bin/rails generate migration AddFieldToModel`
- Indexes: Always add for foreign keys and lookup fields
- Seeds: Development seeds in `db/seeds/development.rb`

### API Development
- Version all endpoints (v1, v2)
- Use `Api::V1::ApplicationController` as base
- JWT authentication handled by BulletTrain
- Add to `config/routes/api/v1.rb`

### Testing Guidelines
- Test files mirror app structure
- Use factories for test data (FactoryBot)
- VCR for external API calls
- System tests for critical user flows

## Important Notes

1. **Always scope to teams**: Use `current_team` in controllers
2. **Security first**: Validate all inputs, scan generated code
3. **Use existing patterns**: Check similar files before implementing
4. **Background jobs for AI**: Never call AI APIs synchronously
5. **Follow BulletTrain conventions**: Especially for controllers and models
6. **Super-scaffolding strategy**: Use for any model needing CRUD/API endpoints
7. **Dual UI approach**: Admin features in `/account/`, public UX in `/public/`

## BulletTrain Role System (CRITICAL)

**Understanding BulletTrain Roles - MEMORIZE THIS:**

1. **Role Storage**: 
   - Roles are stored in `membership.role_ids` as a JSONB array (NOT a single role field)
   - Example: `["admin"]` or `["editor", "viewer"]` or `["default"]`

2. **Role Definitions** (in `config/models/roles.yml`):
   - **admin**: Full management permissions, includes editor role
   - **editor**: Can manage specific models (e.g., TangibleThings)
   - **default**: Basic permissions (read, create some models)

3. **Key Concepts**:
   - **team_id = organization_id** in our architecture
   - Teams represent organizations/companies
   - Each membership connects a user to a team with specific roles

4. **Accessing Roles in Code**:
   ```ruby
   # Get primary role (highest permission)
   primary_role = membership.role_ids.include?('admin') ? 'admin' : 
                  membership.role_ids.include?('editor') ? 'editor' : 
                  membership.role_ids.first || 'default'
   
   # Check if user has admin role
   is_admin = membership.role_ids.include?('admin')
   
   # Get all roles
   all_roles = membership.role_ids || ['default']
   ```

5. **Permission Hierarchy**:
   - admin > editor > default
   - Admins automatically get all editor permissions
   - Use CanCan's `permit` method for role-based authorization

## Debugging Tips

```ruby
# Rails console helpers
app.account_apps_path       # Test routes
app.get '/apps'            # Make requests
reload!                    # Reload code

# Check SQL queries
App.published.to_sql       # See generated SQL
App.published.explain      # Query execution plan

# Inspect background jobs
require 'sidekiq/api'
Sidekiq::Queue.new.size    # Queue size
Sidekiq::RetrySet.new.size # Failed jobs
```

## Module Loading & Testing Notes

### AI Services Module Naming
The AI services are defined with uppercase `AI` module but Rails/Zeitwerk may have loading issues:
- Services are located in `app/services/ai/`
- Module is defined as `module AI` (uppercase)
- When testing, may need explicit requires:
  ```ruby
  require_relative 'app/services/ai/open_router_client'
  require_relative 'app/services/ai/app_spec_builder'
  require_relative 'app/services/ai/app_generator_service'
  ```

### Testing App Generation
To test the app generation flow:
1. Ensure `OPENROUTER_API_KEY` is set in `.env.development.local`
2. Use the test scripts in project root:
   - `test_app_generation_detailed.rb` - Full generation test
   - `test_openrouter_api.rb` - API connectivity test
   - `test_simple_api.rb` - Direct HTTP test

### Testing Database Management System
To test the complete database dashboard system:
1. Ensure Supabase credentials are configured in `.env.development.local`
2. Use the database test scripts in project root:
   - `test_database_dashboard_flow.rb` - Complete database dashboard test
   - `test_ai_chat_integration.rb` - AI database planning integration test
   - `test_live_ai_message.rb` - End-to-end AI message system test

**Required Environment Variables:**
```bash
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_KEY=your-service-role-key
SUPABASE_ANON_KEY=your-anon-key  # ⚠️ Must restart Rails after adding
```

### Current Status (Phase 3A Complete - Database Management System)
- ✅ **Lovable.dev-style UI** implemented (split screen, chat, preview, code editor)
- ✅ **App generation models and services** created
- ✅ **Chat-based iterative improvement system**
- ✅ **Live preview with iframe rendering**
- ✅ **File browser with syntax highlighting**
- ✅ **Dark theme professional editor experience**
- ✅ **Base44-style Database Dashboard** with full CRUD interface
- ✅ **Supabase integration** with multi-tenant row-level security
- ✅ **Dynamic schema management UI** (create/edit tables and columns)
- ✅ **Real-time table data viewer** with add/edit/delete records
- ✅ **AI orchestration database awareness** (schema planning integrated)
- ✅ **OAuth and API integration system** via Cloudflare Workers
- ✅ **Multi-step AI orchestration** with validation and improvement cycles
- ⚠️ **Environment**: Restart Rails server after adding `SUPABASE_ANON_KEY` to `.env.development.local`

### Database Management System (NEW)
**Complete Base44-style database management now available:**

#### Dashboard Interface
- **Dashboard Tab**: Added beside Preview/Files in app editor
- **Professional UI**: Base44-inspired design with dark theme support
- **Real-time Updates**: Live table/record management with notifications

#### Schema Management
- **Dynamic Table Creation**: Name, description, validation
- **Advanced Column Types**: text, number, boolean, date, datetime, select, multiselect
- **Schema Editor**: Visual column management with type-specific options
- **Validation**: Column name patterns, required fields, type checking

#### Data Management  
- **Table Data Viewer**: Full CRUD interface for records
- **Dynamic Forms**: Auto-generated forms based on column schema
- **Type-specific Inputs**: Proper input types for each column type
- **Batch Operations**: Select, multiselect with option parsing

#### Supabase Integration
- **Multi-tenant Architecture**: App-specific schemas (`app_{id}_tablename`)
- **Row Level Security**: Automatic RLS policies for data isolation
- **Service Layer**: Complete `Supabase::AppDatabaseService` for operations
- **SQL Generation**: Type mapping and DDL generation

#### AI Integration
- **Schema Planning**: AI analysis prompts include database capabilities
- **Context Awareness**: AI knows about existing tables and columns
- **Database Keywords**: Strong integration (DATABASE, SCHEMA, TABLE, SUPABASE found)
- **Multi-step Orchestration**: Database changes included in AI workflow

#### Testing & Validation
✅ **Database Dashboard Test**: All components tested and functional
✅ **AI Chat Integration Test**: Schema planning verified in AI prompts  
✅ **Live Message Test**: End-to-end system integration confirmed
✅ **CRUD Interface Test**: Full create/read/update/delete operations

## Additional Documentation

- Main docs: `/docs/` directory
- AI context: `/docs/ai-context.md` (comprehensive guide)
- **AI Orchestration Standards**: `/docs/ai-orchestration-design-standards.md` ⭐ **CRITICAL**
- AI platform constraints: `/docs/ai-app-development-constraints.md`
- OpenRouter monitoring: `/docs/openrouter-kimi-monitoring.md`
- **Supabase Integration**: `/docs/supabase-integration.md` (auth sync & usage)
- Business plan: `/docs/business-plan.md`
- Architecture: `/docs/architecture.md`
- BulletTrain docs: https://bullettrain.co/docs

## Key Integration Points

### Supabase Authentication Sync
- **Purpose**: Hybrid auth - Rails primary, Supabase for generated apps
- **When to use**: User lifecycle events, OAuth logins, admin monitoring
- **Admin panel**: `/account/supabase_sync` (requires admin role)
- **Key commands**: 
  - `rake supabase:sync_all_users` - Batch sync existing users
  - `rake supabase:sync_status` - Check sync health
  - `rake supabase:sync_user[email]` - Sync specific user
- **Background jobs**: `SyncUsersToSupabaseJob`, `SupabaseAuthSyncJob`
- **Full docs**: `/docs/supabase-integration.md`

### AI Generation with Function Calling
- **Primary model**: Kimi K2 via OpenRouter (cost-effective)
- **Fallback model**: Claude Sonnet (reliable function calling)
- **Key service**: `AI::OpenRouterClient#chat_with_tools`
- **Progress tracking**: Real-time updates via `AppChatMessage` broadcasts
- **Error handling**: Automatic retry, timeout management, JSON parsing elimination

### Database Management System
- **Dashboard location**: Dashboard tab in app editor
- **Supabase integration**: Multi-tenant with RLS policies
- **Service**: `Supabase::AppDatabaseService`
- **Schema format**: `app_{id}_tablename` for isolation
- **AI awareness**: Database schema included in generation prompts

### Mobile UI Patterns
- **Editor layout**: Responsive with floating edit button
- **Chat overlay**: Full-screen on mobile via `openMobileChat()`
- **Toggle style**: Pill buttons on mobile, underline on desktop
- **Key controller**: `editor_layout_controller.js`

## CRITICAL: AI Orchestration Quality Standards

**📍 Location**: `/docs/ai-orchestration-design-standards.md`  
**📅 Last Updated**: August 4, 2025  
**🎯 Purpose**: Maintains Base44-level sophisticated app generation quality

This document defines our enhanced AI orchestration approach that enables professional-grade app generation. **Any changes to AI prompts in `app/services/ai/open_router_client.rb` MUST be reflected in this document immediately** to prevent quality regression.