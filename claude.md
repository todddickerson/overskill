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

## Deployment Architecture (V4 - VITE BUILD SYSTEM) ✅ FINALIZED

### Infrastructure Philosophy
- **Professional Stack**: Vite + TypeScript + React Router + Cloudflare Workers
- **Cloudflare Worker Builds**: Build system runs via Cloudflare API (no CLI)
- **Simple Architecture**: ALL apps use Supabase-first approach ($1-2/month)
- **App-Scoped Database**: `app_${APP_ID}_${table}` naming with RLS isolation
- **Dual Build Modes**: Fast dev builds (45s) and optimized prod builds (3min)
- **API-Only Deployment**: Pure HTTP API approach, no Wrangler CLI

### Core Services (V4)

#### 1. **Ai::AppBuilderV4** (Primary orchestrator) ✅ DECIDED
- Template-based generation with shared foundation files
- **Simple architecture ONLY** (no app type detection needed)
- Integration with LineReplaceService and SmartSearchService
- AI retry system (2x maximum) then human intervention
- Token usage tracking per app_version for future billing
- Path: `app/services/ai/app_builder_v4.rb`

#### 2. **Ai::SharedTemplateService** (Template system) ✅ DECIDED
- Core foundation files ALL apps need (auth, routing, database)
- **Git repository storage** at `/app/templates/shared/`
- TypeScript + React Router + Tailwind + shadcn/ui
- App-scoped Supabase client with debugging wrapper
- Path: `app/services/ai/shared_template_service.rb`

#### 3. **Deployment::ViteBuilderService** (Build pipeline) ✅ DECIDED
- **Cloudflare Worker builds** via API (no Docker/ECS needed)
- **Development Mode**: Fast builds (45s) for rapid iteration
- **Production Mode**: Full optimization with hybrid assets (3min)
- Worker runtime executes Node.js + Vite builds
- Path: `app/services/deployment/vite_builder_service.rb`

#### 4. **Deployment::CloudflareApiClient** (API-only deployment) ✅ DECIDED
- **Pure API approach** - no Wrangler CLI dependency
- Worker deployment, R2 uploads, secret management via API
- AppEnvVar integration with automatic Cloudflare sync
- Route configuration and domain management
- Path: `app/services/deployment/cloudflare_api_client.rb`

### Database Architecture ✅ DECIDED

#### File Storage Strategy
Uses **existing database tables** (analyzed and perfect for V4):

```ruby
# Current structure works perfectly for V4:
class AppFile < ApplicationRecord
  belongs_to :app, :team
  validates :path, :content, presence: true    # 'src/App.tsx' + content
end

class AppVersion < ApplicationRecord
  has_many :app_version_files  # Tracks all changes
  # AI-generated display names via OpenRouter Gemini Flash
end

class AppVersionFile < ApplicationRecord  
  belongs_to :app_version, :app_file
  enum :action, { created: 'create', updated: 'update', deleted: 'delete' }
end

class AppEnvVar < ApplicationRecord
  belongs_to :app
  # System defaults: SUPABASE_URL, APP_ID, OWNER_ID, ENVIRONMENT
  after_commit :sync_to_cloudflare  # Automatic Worker sync
end
```

#### App-Scoped Database
```typescript
// Template: /app/templates/shared/database/app-scoped-db.ts
class AppScopedDatabase {
  from(table: string) {
    const scopedTable = `app_${this.appId}_${table}`;
    console.log(`🗃️ [${this.appId}] Querying: ${scopedTable}`);
    return this.supabase.from(scopedTable);
  }
}
```

### Environment Variable Strategy

#### Public Variables (Safe for client)
```javascript
// Injected into HTML/accessible in browser
VITE_APP_ID
VITE_SUPABASE_URL
VITE_SUPABASE_ANON_KEY
VITE_ENVIRONMENT
```

#### Secret Variables (Worker-only)
```javascript
// Never exposed to client, only in Worker env
SUPABASE_SERVICE_KEY
GOOGLE_CLIENT_SECRET
STRIPE_SECRET_KEY
OPENAI_API_KEY
```

#### Setting Variables (No Wrangler)
```ruby
# Via Cloudflare API in CloudflarePreviewService
def set_worker_secret(worker_name, key, value)
  self.class.patch(
    "/accounts/#{@account_id}/workers/scripts/#{worker_name}/secrets",
    body: { name: key, text: value, type: 'secret_text' }.to_json
  )
end
```

### Worker Architecture

#### Module Format (Modern)
```javascript
export default {
  async fetch(request, env, ctx) {
    // env contains all variables and secrets
    // Secrets are never exposed to client
    return handleRequest(request, env, ctx);
  }
};
```

#### API Proxy Pattern
```javascript
// Supabase proxy with service key
if (path.startsWith('/api/db/')) {
  const serviceKey = env.SUPABASE_SERVICE_KEY; // Secret
  // Proxy request with elevated permissions
}
```

### App-Scoped Database Architecture

```typescript
// ALL apps include this wrapper (transparent + debuggable)
class AppScopedDatabase {
  private appId: string;
  
  from(table: string) {
    const scopedTable = `app_${this.appId}_${table}`;
    // Development logging: "🗃️ Querying table: app_123_todos"
    return this.supabase.from(scopedTable);
  }
  
  getTableName(table: string): string {
    return `app_${this.appId}_${table}`;
  }
}

// Usage in generated code:
const todos = await db.from('todos').select('*');
// Actually queries: app_123_todos
```

### Consistent Simple Architecture (All Apps)

- **ALL Apps**: Supabase-first, minimal edge complexity ($1-2/month per app)
- **Authentication**: Supabase Auth with built-in OAuth support
- **Database**: App-scoped tables with automatic RLS isolation
- **Static Assets**: R2 for CDN performance only
- **No Complex Services**: No KV storage, Cache API, or edge analytics

### V4 Deployment Flow

```ruby
# 1. Generate app with AI (simple architecture for all)
builder = Ai::AppBuilderV4.new(chat_message)

# 2. Generate shared foundation + app-specific features  
builder.generate_shared_foundation  # Auth, routing, app-scoped DB
builder.generate_app_features       # Supabase-first approach

# 3. Build with appropriate optimization
case user_intent
when /deploy|production/
  result = ProductionOptimizedBuilder.new(app).build!  # 3min optimized
else
  result = FastDevelopmentBuilder.new(app).build!     # 45s fast
end

# 4. App available at:
# Development: https://preview-{app-id}.overskill.app
# Production: https://app-{app-id}.overskill.app
```

## AI Considerations

### Claude 4 Series (Latest - Recommended)
- **Claude Opus 4.1**: Released August 5, 2025 - Most capable model
  - API Model ID: `claude-opus-4-1-20250805`
  - Best for: Complex, long-running tasks, agent workflows
  - Performance: 72.5% on SWE-bench, 43.2% on Terminal-bench
  - Pricing: $15/$75 per million tokens (input/output)
  - Features: Extended thinking, tool use, 200k context window
  - API Docs: https://docs.anthropic.com/en/docs/about-claude/models

- **Claude Sonnet 4**: Released May 22, 2025 - Best for coding
  - API Model ID: `claude-sonnet-4-20250514`
  - Performance: 72.7% on SWE-bench (state-of-the-art)
  - Pricing: $3/$15 per million tokens (input/output)
  - Features: Superior coding and reasoning, follows instructions precisely
  - Currently using: `claude-3-5-sonnet-20241022` (latest available)

### GPT-5 Series
- **GPT-5**: Released August 7, 2025 - Unified AI with reasoning
  - Models: gpt-5, gpt-5-mini, gpt-5-nano
  - Direct OpenAI API integration with function calling
  - Pricing: $1.25/$10 per 1M input/output tokens (gpt-5)
  - Features: PhD-level intelligence, unified reasoning, no temperature control
  - Note: Only supports default temperature, use max_completion_tokens instead of max_tokens

### Legacy Models
- **Claude 3.5 Sonnet**: Model ID `claude-3-5-sonnet-20241022` - Current fallback
- **Claude 3 Opus**: Model ID `claude-3-opus-20240229` - Previous premium model
- **Kimi-K2**: May timeout with function calling, use StructuredAppGenerator instead

## AI App Generation System (V4 - TEMPLATE-BASED)

### Key Components
- **AI_APP_STANDARDS.md**: PRO MODE ONLY - Vite + TypeScript + React Router (INSTANT MODE removed)
- **Ai::AppBuilderV4**: Template-based orchestrator with Claude 4 conversation loop
- **Ai::SharedTemplateService**: Core foundation files (auth, routing, database wrapper)
- **Integration Services**: LineReplaceService (90% token savings) + SmartSearchService
- **Claude 4 Primary**: Extended thinking with conversation loop for multi-file generation

### V4 Generation Flow
1. **Simple Architecture**: All apps use consistent Supabase-first approach
2. **Shared Foundation**: Generate core files all apps need (templates)
3. **AI Customization**: Claude 4 generates app-specific features via conversation
4. **Surgical Edits**: Use LineReplaceService for minimal changes
5. **Build & Deploy**: Fast dev (45s) or optimized prod (3min) via API only

### Claude 4 Conversation Loop
```ruby
# Claude only creates 1-2 files per API call
def generate_with_claude_conversation(files_needed)
  files_created = []
  
  files_needed.each_slice(2) do |batch|
    response = claude_create_files(batch)
    files_created.concat(response[:files])
    broadcast_progress(files_created)
  end
end
```

### V4 Tool Integration
- **LineReplaceService**: Surgical edits with ellipsis support (90% token savings)
- **SmartSearchService**: Find existing components to prevent duplicates
- **App-Scoped Database**: Automatic `app_${id}_${table}` naming
- **Cloudflare Optimization**: Hybrid asset strategy for 1MB worker limit

### Testing V4 Generation
```ruby
# Test V4 orchestrator
rails console
message = AppChatMessage.create!(content: "Build a todo app", user: user)
builder = Ai::AppBuilderV4.new(message)
builder.execute!
```

## DevUX and Testing Tools

### Deployment Testing Suite
Comprehensive test scripts for verifying deployed app functionality:

#### Core Test Scripts (JavaScript/Node.js)
- **`test_todo_deployment.js`** - Main deployment verification
  - Tests app accessibility and HTTP status
  - Analyzes HTML structure for React elements
  - Detects TypeScript transformation errors
  - Validates todo app content and patterns
  - Generates comprehensive test reports

- **`test_app_functionality.js`** - JavaScript/React functionality testing
  - Tests main script loading and execution
  - Analyzes React component patterns
  - Checks for modern JavaScript syntax
  - Validates environment variable injection
  - Provides code samples and detailed analysis

- **`test_app_components.js`** - Component-level testing
  - Tests individual React component files
  - Validates CSS and styling resources
  - Checks for proper React hooks usage
  - Analyzes JSX transformation quality

- **`test_dev_url.js`** - Development URL testing
  - Tests dev.overskill.app accessibility
  - Validates development environment setup
  - Checks for proper CNAME configuration

#### Browser-based Testing
- **`test_deployed_todo_app.html`** - Interactive browser test
  - Live iframe testing of deployed apps
  - Real-time JavaScript error detection
  - Cross-origin frame testing capabilities
  - Visual status reporting with styled interface
  - Screenshot placeholders for manual testing

#### Usage Examples
```bash
# Run comprehensive deployment test
node test_todo_deployment.js

# Test React functionality specifically  
node test_app_functionality.js

# Analyze all app components
node test_app_components.js

# Test development URLs
node test_dev_url.js

# Open browser-based interactive test
open test_deployed_todo_app.html
```

#### Key Testing Patterns
- **TypeScript Error Detection**: Specifically looks for transformation issues
  - "Invalid regular expression flags"
  - "missing ) after argument list" 
  - Syntax errors in transpiled JavaScript
  
- **React Validation**: Checks for proper React loading
  - useState/useEffect hooks
  - JSX rendering
  - Component mounting
  - Modern JavaScript patterns

- **Todo App Validation**: Verifies app-specific functionality
  - Task management features
  - State persistence
  - UI interaction patterns
  - External library integration

#### Test Report Generation
All test scripts generate detailed reports including:
- HTTP status codes and response analysis
- JavaScript error detection and categorization
- React component structure validation
- Performance and loading metrics
- Specific recommendations for fixes

These tools are essential for verifying that Cloudflare Worker deployments are functioning correctly and that TypeScript transformation is working without introducing runtime errors.

### Autonomous Testing System
Comprehensive AI generation quality monitoring and testing framework:

#### Main Testing Script
- **`test_autonomous.rb`** - CLI interface for autonomous testing
  - `ruby test_autonomous.rb quick` - Fast GPT-5 demo (30 seconds, recommended first test)
  - `ruby test_autonomous.rb health` - Single health check test
  - `ruby test_autonomous.rb suite` - Full comprehensive test suite (4 app types)
  - `ruby test_autonomous.rb status` - Show current system metrics
  - `ruby test_autonomous.rb monitor [min]` - Continuous monitoring

#### Supporting Files
- **`lib/autonomous_testing_system.rb`** - Production testing system with metrics
- **`gpt5_autonomous_demo.rb`** - Proven GPT-5 generation demo (100% success rate)

#### Key Features
- **Real-time Progress**: Shows files being created during generation
- **Quality Metrics**: Success rate, generation time, pattern matching
- **GPT-5 Integration**: Direct OpenAI API with proper temperature handling
- **Comprehensive Scenarios**: Counter, todo, calculator, weather apps
- **Continuous Monitoring**: Background quality assessment
- **Detailed Reporting**: JSON logs and test reports in test_results/

#### Usage for Development
```bash
# Quick verification GPT-5 is working
ruby test_autonomous.rb quick

# Full quality assessment
ruby test_autonomous.rb suite

# Background monitoring every hour
ruby test_autonomous.rb monitor 60
```

This system enables rapid iteration and quality monitoring of AI app generation capabilities.