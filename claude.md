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

## Tips
- Utilize Perplexity MCP server for research or to confirm how things work
- Utilize Desktop commander if needed for interacting with processes
- Utilize Playwright MCP for interacting with web browser in real time, analyze screenshots to confirm actions before proceeding.
- Utilize Context7 MCP for documentation look ups
- Explore then Plan full MD file plans for larger projects and phases.  Have Perplexity research review your plan, consider feedback in context of our application and update plan.  Share files/etc with the MCP if it might get more relevant results.
- Apps we build are based off /app/services/ai/templates/overskill_20250728 it should be a GH repo we can commit/modify and push, new apps will be based off latest version of it.

## For Apps we generate
  The deployment flow is now:
  1. ProcessAppUpdateJobV4 runs AI generation
  2. Files are created immediately in database
  3. App version is created
  4. DeployAppJob queues for deployment
  5. AppFilesInitializationJob runs async for R2 optimization

## Implementation Plans & Documentation
<!-- Add new implementation plans here after they are committed and finalized -->
- **WFP_IMPLEMENTATION_PLAN.md** - Workers for Platforms complete architecture (✅ Implemented)
- **WFP_IMPLEMENTATION_STATUS.md** - Current WFP deployment status and results
- **DOMAIN_STRATEGY.md** - Workers.dev vs custom domain analysis  
- **CRITICAL_NEXT_STEPS.md** - Immediate action items for WFP
- **GITHUB_ACTIONS_WFP_DEPLOYMENT.md** - Complete GitHub Actions + WFP deployment architecture (✅ Production Ready)
- **COMPREHENSIVE_WFP_IMPLEMENTATION_PLAN.md** - ✨ NEW: Integrated live preview, tool streaming, and 50k+ app scale (Jan 2025)
- **LIVE_PREVIEW_IMPLEMENTATION_PLAN.md** - Live preview with WFP (Coordinated with comprehensive plan)
- **WEBSOCKET_TOOL_STREAMING_STRATEGY.md** - Real-time tool execution streaming (Coordinated with comprehensive plan)
- **DEPLOYMENT_URL_PATTERNS.md** - ⚠️ CRITICAL: Correct URL formats for deployed apps (Use overskill.app domain, NOT workers.dev)
<!-- Add new plans above this line -->

## Project Overview

OverSkill is an AI-powered app marketplace platform built with Ruby on Rails (BulletTrain framework). It enables non-technical users to create, deploy, and monetize applications using natural language.

## Workers for Platforms (WFP) Architecture - January 2025

### Implementation Status
Complete implementation supporting 50,000+ apps with Workers for Platforms. See documentation:
- **WFP_IMPLEMENTATION_PLAN.md** - Full architecture and deployment strategy
- **WFP_IMPLEMENTATION_STATUS.md** - Current deployment status and results
- **DOMAIN_STRATEGY.md** - Workers.dev vs custom domain analysis
- **CRITICAL_NEXT_STEPS.md** - Immediate action items for WFP

### WFP Architecture Summary
```
AI Generator (v5) → GitHub Repository → WFP Deployment → Dispatch Router
```
- **Repository-per-app**: Maintained for transparency and version control
- **Workers for Platforms**: Unlimited app deployments via dispatch namespaces
- **Cost**: ~$50-100/month for 1,000 apps (96% savings vs standard Workers)
- **Namespaces**: Include Rails.env (overskill-development-preview, etc.)

### Key Services
- **Deployment::WorkersForPlatformsService** - Main WFP deployment service
- **Deployment::GithubRepositoryService** - GitHub repo creation via forking
- **Deployment::GithubAppAuthenticator** - GitHub App auth (ID: 1815066)

### Infrastructure Philosophy
- **Professional Stack**: Vite + TypeScript + React Router + Cloudflare Workers
- **Cloudflare Worker Builds**: Build system runs via Cloudflare API (no CLI)
- **Simple Architecture**: ALL apps use Supabase-first approach ($1-2/month)
- **App-Scoped Database**: `app_${APP_ID}_${table}` naming with RLS isolation
- **Dual Build Modes**: Fast dev builds (45s) and optimized prod builds (3min)
- **API-Only Deployment**: Pure HTTP API approach, no Wrangler CLI

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
