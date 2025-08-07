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

## Deployment Architecture (UPDATED)

### Infrastructure Philosophy
- **Lean Stack**: Cloudflare Workers + R2 + KV + Supabase only
- **No Build Tools**: Direct deployment via Cloudflare API
- **No Wrangler CLI**: Use Cloudflare API for all operations
- **Fast Preview**: < 3 seconds using CDN React + on-the-fly transformation
- **Module Workers**: Modern format for better secret handling

### Deployment Services

#### 1. **FastPreviewService** (Primary - < 3s deploy)
- Instant preview without build step
- Uses CDN React (unpkg/esm.sh)
- On-the-fly TypeScript transformation
- Module worker format with proper env handling
- Path: `app/services/deployment/fast_preview_service.rb`

#### 2. **CloudflarePreviewService** (Base service)
- Handles worker upload and route configuration
- Environment variable management via API
- Supports preview/staging/production environments
- Path: `app/services/deployment/cloudflare_preview_service.rb`

#### 3. **CloudflareSecretService** (Lean infrastructure)
- Manages secrets via Cloudflare API only
- R2 bucket integration for assets
- KV namespace for sessions
- No external dependencies
- Path: `app/services/deployment/cloudflare_secret_service.rb`

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

### Fast Preview Implementation

1. **No Build Step**: Direct file serving with transformation
2. **CDN Dependencies**: React, Babel via unpkg
3. **Import Maps**: ES module resolution
4. **TypeScript Transform**: Basic on-the-fly conversion
5. **Instant Deploy**: < 3 seconds from save to preview

### Deployment Flow

```ruby
# 1. Generate app with AI
generator = Ai::StructuredAppGenerator.new(app)
generator.generate!(prompt)

# 2. Deploy instant preview (< 3s)
preview_service = Deployment::FastPreviewService.new(app)
result = preview_service.deploy_instant_preview!

# 3. App available at:
# https://preview-{app-id}.overskill.app
```

## AI Considerations

- **Kimi-K2**: May timeout with function calling, use StructuredAppGenerator instead
- **Fallback**: Claude Sonnet for reliable function calling
- **Workaround**: StructuredAppGenerator avoids function calls entirely

## AI App Generation System (Enhanced)

### Key Components
- **AI_APP_STANDARDS.md**: Comprehensive standards automatically included in every AI generation request
- **AppUpdateOrchestratorV2**: Enhanced orchestrator with tool calling for incremental file updates
- **Real-time Progress**: Shows files being created/edited in real-time during generation
- **30-minute timeout**: Extended from 10 minutes to handle complex app generation
- **Function/Tool Calling**: Uses OpenRouter's tool calling API for structured operations

### How It Works
1. **Analysis Phase**: AI analyzes app structure and user request
2. **Planning Phase**: Creates detailed execution plan with tool definitions
3. **Execution Phase**: Uses tool calling to incrementally update files with progress broadcasts
4. **Validation Phase**: Confirms all changes and updates preview

### Tool Functions Available
- `read_file`: Read complete file content
- `write_file`: Create or overwrite files
- `update_file`: Find/replace within files
- `delete_file`: Remove files
- `broadcast_progress`: Send real-time updates to user

### Testing AI Generation
```ruby
# Test the new orchestrator directly
rails console
message = AppChatMessage.last  # Get a test message
orchestrator = Ai::AppUpdateOrchestratorV2.new(message)
orchestrator.execute!
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