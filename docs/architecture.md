# OverSkill Technical Architecture

## System Overview

OverSkill uses a modern, scalable architecture designed for global performance and minimal operational overhead. The platform consists of three main components:

1. **Control Plane** (Rails + BulletTrain) - User management, marketplace, billing
2. **AI Engine** (OpenRouter + Multiple Providers) - App generation and optimization  
3. **App Runtime** (Cloudflare Workers + R2) - Global app hosting and delivery

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│                 │     │                 │     │                 │
│  Web Frontend   │────▶│  Rails Backend  │────▶│   AI Services   │
│  (Hotwire)      │     │  (Control)      │     │  (Generation)   │
│                 │     │                 │     │                 │
└─────────────────┘     └────────┬────────┘     └─────────────────┘
                                 │
                                 ▼
                        ┌─────────────────┐
                        │                 │
                        │ Cloudflare Edge │
                        │ (App Delivery)  │
                        │                 │
                        └─────────────────┘
```

## Infrastructure Stack

### Primary Services

#### Rails Application (Control Plane)
- **Hosting**: Render.com or Railway
- **Framework**: Rails 7.1 + BulletTrain Pro
- **Database**: PostgreSQL 14+
- **Cache**: Redis 7+
- **Jobs**: Sidekiq
- **Cost**: ~$25-50/month

#### AI Integration
- **Primary**: OpenRouter API
  - Kimi K2 ($1/M input, $3/M output tokens)
  - DeepSeek v3 (backup)
  - Gemini Flash 1.5 (quick tasks)
- **Fallback**: Direct provider APIs
- **Cost**: ~$0.001-0.05 per app

#### App Hosting (Runtime)
- **Static Files**: Cloudflare R2
  - $0.015/GB storage
  - No egress fees
- **Edge Computing**: Cloudflare Workers
  - 10M requests free
  - $0.50/million after
- **Database**: Shared Supabase
  - $25/month unlimited API calls
- **Cost**: ~$0.001 per app/month

### Architecture Decisions

#### Why This Stack?

1. **Rails + BulletTrain**
   - Complete SaaS framework
   - Multi-tenancy built-in
   - Stripe integration ready
   - Fast development

2. **Cloudflare Workers + R2**
   - Global edge network (300+ locations)
   - No cold starts
   - Automatic scaling
   - Minimal cost

3. **Shared Supabase**
   - Row-level security for isolation
   - Real-time subscriptions
   - Built-in auth per app
   - Scales to 10,000+ apps

4. **OpenRouter for AI**
   - Multiple model access
   - Automatic fallbacks
   - Unified billing
   - Best prices

## Data Architecture

### Database Schema (PostgreSQL)

```sql
-- Core Tables (via BulletTrain)
users
teams  
memberships
oauth_applications

-- OverSkill Tables
creator_profiles
  - user_id (FK)
  - username (unique)
  - level
  - total_earnings
  - verification_status

apps
  - team_id (FK)
  - creator_profile_id (FK)
  - name
  - slug (unique)
  - status
  - base_price
  - total_revenue

app_generations
  - app_id (FK)
  - prompt
  - ai_model
  - tokens_used
  - cost
  - status

app_files
  - app_id (FK)
  - path
  - content
  - checksum

purchases
  - user_id (FK)
  - app_id (FK)
  - amount
  - stripe_payment_intent_id
  - status
```

### Supabase Schema (Multi-tenant Apps)

```sql
-- Shared tables with RLS
app_users
  - id
  - app_id (for RLS)
  - email
  - created_at

app_data
  - id
  - app_id (for RLS)
  - user_id
  - data (JSONB)
  - created_at

-- Row Level Security
CREATE POLICY "Users can only see their app's data"
ON app_data
FOR ALL
USING (app_id = current_setting('app.id')::uuid);
```

## AI Integration Architecture

### Generation Pipeline

```
User Prompt → Enhance → Generate → Validate → Deploy
     │           │          │          │         │
     ▼           ▼          ▼          ▼         ▼
   Input    Smart Pro-   Kimi K2   Security   Workers
 Validation  mpting      API Call   Scan       + R2
```

### AI Service Implementation

```ruby
# app/services/ai/generation_pipeline.rb
class AI::GenerationPipeline
  def initialize(prompt, user, options = {})
    @prompt = prompt
    @user = user
    @options = options
  end
  
  def execute
    # 1. Validate input
    validate_prompt!
    
    # 2. Check user limits
    check_generation_limits!
    
    # 3. Enhance prompt
    enhanced = enhance_prompt
    
    # 4. Generate with AI
    result = generate_app(enhanced)
    
    # 5. Security scan
    scan_results = scan_code(result[:files])
    
    # 6. Create app records
    app = create_app(result) if scan_results[:safe]
    
    # 7. Deploy async
    AppDeploymentJob.perform_later(app) if app
    
    app
  end
  
  private
  
  def generate_app(prompt)
    AI::Providers::KimiK2.new.generate(
      prompt: prompt,
      max_tokens: 8000,
      temperature: 0.7
    )
  rescue AI::RateLimitError
    # Fallback to DeepSeek
    AI::Providers::DeepSeek.new.generate(prompt: prompt)
  end
end
```

### Prompt Engineering System

```ruby
# Structured prompts for consistent output
class AI::PromptTemplates
  TEMPLATES = {
    saas_app: {
      system: "You are an expert SaaS developer...",
      structure: {
        files: ["index.html", "app.js", "styles.css"],
        features: ["auth", "dashboard", "billing"]
      }
    },
    landing_page: {
      system: "You are a conversion-focused designer...",
      structure: {
        files: ["index.html", "styles.css"],
        features: ["hero", "cta", "testimonials"]
      }
    }
  }
  
  def self.for_type(app_type)
    TEMPLATES[app_type] || TEMPLATES[:general]
  end
end
```

## Deployment Architecture

### App Build & Deploy Pipeline

```
AI Generated Files → Build Process → Deploy to Edge
        │                 │                │
        ▼                 ▼                ▼
   Local Files      Webpack/Vite    Upload to R2 +
                    Bundle Assets    Update Worker
```

### Cloudflare Worker Architecture

```javascript
// Single worker handles all app routing
export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const hostname = url.hostname;
    
    // Extract app identifier
    const subdomain = hostname.split('.')[0];
    
    // Route preview vs production
    let appPath;
    if (subdomain.startsWith('preview--')) {
      // preview--app-name-hash.overskill.app
      appPath = handlePreview(subdomain);
    } else {
      // app-name.overskill.app
      appPath = `apps/${subdomain}`;
    }
    
    // Fetch from R2
    const object = await env.R2.get(`${appPath}${url.pathname}`);
    
    if (!object) {
      return handleNotFound(request);
    }
    
    // Return with caching headers
    return new Response(object.body, {
      headers: {
        'Content-Type': object.httpMetadata.contentType,
        'Cache-Control': 'public, max-age=3600',
        'X-App-Id': subdomain
      }
    });
  }
};
```

### Zero-Downtime Deployment

```ruby
class AppDeployer
  def deploy(app)
    # 1. Build assets
    build_result = build_app_assets(app)
    
    # 2. Upload to R2 (new version)
    r2_path = upload_to_r2(
      app_slug: app.slug,
      files: build_result[:files],
      version: app.version
    )
    
    # 3. Update Worker routing (atomic)
    update_worker_routes(
      app_slug: app.slug,
      new_path: r2_path
    )
    
    # 4. Purge CDN cache
    purge_cloudflare_cache(app.production_url)
    
    # 5. Cleanup old versions
    cleanup_old_versions(app, keep: 3)
  end
end
```

## Security Architecture

### Multi-Layer Security

#### 1. Input Validation
```ruby
class SecurityValidator
  BLOCKED_PATTERNS = [
    /eval\s*\(/,          # No eval
    /exec\s*\(/,          # No exec
    /<script.*src=/i,     # No external scripts
    /document\.cookie/,    # No cookie access
  ]
  
  def validate_code(files)
    threats = []
    files.each do |file|
      content = file[:content]
      BLOCKED_PATTERNS.each do |pattern|
        if content.match?(pattern)
          threats << {
            file: file[:path],
            pattern: pattern.source,
            severity: 'high'
          }
        end
      end
    end
    threats
  end
end
```

#### 2. Runtime Isolation
- Each app runs in isolated Cloudflare Worker
- No access to other apps' data
- Supabase RLS enforces data boundaries
- No server-side code execution

#### 3. Platform Security
- Rails app uses standard security headers
- CSRF protection via BulletTrain
- Strong parameters for all inputs
- Rate limiting on all endpoints

### Authentication Flow

```
User → Rails App → JWT Token → Cloudflare Worker → Supabase
         │             │              │                │
         ▼             ▼              ▼                ▼
     Devise Auth   Sign Token    Verify Token    RLS Check
```

## Performance Optimization

### Caching Strategy

#### Rails Application
```ruby
# Fragment caching for expensive views
<% cache ["marketplace", @category, @page] do %>
  <%= render @apps %>
<% end %>

# Redis caching for computed values
Rails.cache.fetch("trending_apps", expires_in: 1.hour) do
  App.calculate_trending.limit(20)
end

# Counter caches for associations
class App < ApplicationRecord
  counter_culture :creator_profile
  counter_culture :team
end
```

#### Edge Caching
```javascript
// Cloudflare Worker caching
const cache = caches.default;

// Check cache first
let response = await cache.match(request);
if (response) return response;

// Fetch and cache
response = await fetchFromR2(request);
ctx.waitUntil(
  cache.put(request, response.clone())
);
```

### Database Optimization

```sql
-- Critical indexes
CREATE INDEX idx_apps_marketplace 
ON apps(status, visibility, created_at DESC)
WHERE status = 'published';

CREATE INDEX idx_purchases_user 
ON purchases(user_id, created_at DESC);

CREATE INDEX idx_app_files_checksum 
ON app_files(app_id, checksum);

-- Materialized views for analytics
CREATE MATERIALIZED VIEW daily_app_stats AS
SELECT 
  app_id,
  DATE(created_at) as date,
  COUNT(*) as purchases,
  SUM(amount) as revenue
FROM purchases
GROUP BY app_id, DATE(created_at);
```

## Monitoring & Observability

### Metrics Collection

```ruby
# config/initializers/metrics.rb
Rails.application.config.after_initialize do
  # Track key business metrics
  ActiveSupport::Notifications.subscribe "app.generated" do |event|
    StatsD.increment("apps.generated")
    StatsD.timing("apps.generation_time", event.duration)
    StatsD.gauge("apps.ai_cost", event.payload[:cost])
  end
end
```

### Health Checks

```ruby
# app/controllers/health_controller.rb
class HealthController < ApplicationController
  def show
    checks = {
      database: check_database,
      redis: check_redis,
      ai_api: check_ai_api,
      cloudflare: check_cloudflare,
      supabase: check_supabase
    }
    
    status = checks.values.all? ? :ok : :service_unavailable
    render json: { status: status, checks: checks }, status: status
  end
end
```

### Error Tracking

```ruby
# config/initializers/sentry.rb
Sentry.init do |config|
  config.dsn = ENV['SENTRY_DSN']
  config.breadcrumbs_logger = [:active_support_logger]
  config.traces_sample_rate = 0.1
  
  # Custom context
  config.before_send = lambda do |event, hint|
    event.user = {
      id: Current.user&.id,
      team_id: Current.team&.id
    }
    event
  end
end
```

## Scaling Strategy

### Horizontal Scaling Points

1. **Rails Application**
   - Add web dynos/containers
   - Scale Sidekiq workers
   - Read replicas for database

2. **AI Processing**
   - Queue jobs by priority
   - Route by model availability
   - Cache common generations

3. **App Delivery**
   - Cloudflare auto-scales
   - R2 handles any volume
   - No scaling needed

### Capacity Planning

```yaml
Current Capacity:
  Rails: 100 requests/second
  AI: 50 generations/minute
  Apps: Unlimited (Cloudflare)
  
At 10K MAU:
  Daily generations: 5,000
  API requests: 2M/day
  Storage: 1TB
  Bandwidth: 10TB/month
  
Scaling Triggers:
  - CPU > 70% sustained
  - Queue depth > 1000
  - Response time > 500ms
  - AI costs > $100/day
```

## Disaster Recovery

### Backup Strategy

```bash
# Automated daily backups
- PostgreSQL: Point-in-time recovery (7 days)
- R2: Cross-region replication
- Redis: RDB snapshots hourly
- Code: Git + CI/CD artifacts

# Recovery Time Objectives
- Database: < 1 hour
- App files: < 5 minutes
- Full platform: < 4 hours
```

### Incident Response

```yaml
Runbook:
  1. Detect via monitoring alerts
  2. Assess impact and severity
  3. Implement immediate mitigation
  4. Communicate to affected users
  5. Root cause analysis
  6. Permanent fix deployment
  7. Post-mortem documentation

On-call rotation:
  - Primary: CTO
  - Secondary: Senior Engineer
  - Escalation: CEO
```

## Cost Analysis

### Infrastructure Costs (Monthly)

```yaml
Fixed Costs:
  Rails Hosting: $25-50
  PostgreSQL: $20
  Redis: $10
  Supabase: $25
  Monitoring: $50
  Total: ~$150

Variable Costs (per 1000 apps):
  AI Generation: $50 (Kimi K2)
  R2 Storage: $0.15 (10GB)
  Worker Requests: $0.50
  Total: ~$51

At Scale (10K apps/month):
  Fixed: $150
  Variable: $510
  Total: $660
  Per App: $0.066
```

### Optimization Opportunities

1. **Cache AI responses** for similar prompts
2. **Batch deployments** to reduce API calls
3. **Progressive enhancement** - start simple
4. **Regional caching** for global users
5. **Compress assets** before storage

---

## Conclusion

This architecture provides:
- **Scalability**: Handle millions of apps
- **Performance**: <100ms global response
- **Reliability**: 99.9% uptime SLA possible
- **Security**: Multi-layer protection
- **Cost-efficiency**: <$0.10 per app

The key insight: **Let specialized services handle complexity** while we focus on the core value proposition - making app creation effortless and profitable.
