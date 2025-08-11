# V4 Implementation Roadmap

**Project**: OverSkill Builder V4 (Vite + Cloudflare Worker Architecture)
**Timeline**: 3 weeks
**Status**: Ready for Implementation

---

## 📅 Weekly Breakdown

### **Week 1: Core Infrastructure** 
*August 12-18, 2025*

#### 🎯 Primary Goals
- Replace V3 orchestrator with V4
- Create shared template system  
- Build Vite pipeline via Cloudflare Workers
- Integrate existing services (LineReplace, SmartSearch)

#### 📋 Specific Deliverables

##### Day 1: V4 Orchestrator Foundation
**Files to Create:**
```ruby
# /app/services/ai/app_builder_v4.rb
module Ai
  class AppBuilderV4
    MAX_RETRIES = 2
    
    def initialize(app_chat_message)
      @app = app_chat_message.app
      @message = app_chat_message
      @app_version = create_new_version
    end
    
    def execute!
      execute_with_retry
    end
    
    private
    
    def execute_with_retry
      # Retry logic with 2x maximum
    end
    
    def execute_generation!
      # 1. Generate shared foundation
      # 2. AI app-specific features  
      # 3. Smart edits via existing services
      # 4. Build and deploy
    end
  end
end
```

**Files to Update:**
```ruby
# /app/models/app.rb - update initiate_generation! method
def initiate_generation!(initial_prompt = nil)
  # Change from V3 to V4
  Rails.logger.info "[App] Using V4 orchestrator for app ##{id}"
  ProcessAppUpdateJobV4.perform_later(message)  # New job
end
```

##### Day 2: Shared Template Service
**Directory to Create:**
```
/app/templates/shared/
├── auth/
│   ├── login.tsx
│   ├── signup.tsx  
│   ├── forgot-password.tsx
│   └── protected-route.tsx
├── database/
│   ├── supabase-client.ts
│   ├── app-scoped-db.ts
│   └── rls-helpers.ts
├── routing/
│   ├── app-router.tsx
│   ├── route-config.ts
│   └── navigation.tsx
└── core/
    ├── package.json
    ├── vite.config.ts
    ├── tailwind.config.js
    ├── tsconfig.json
    └── index.html
```

**Service to Create:**
```ruby  
# /app/services/ai/shared_template_service.rb
module Ai
  class SharedTemplateService
    def initialize(app)
      @app = app
    end
    
    def generate_core_files
      CORE_TEMPLATES.each do |category, files|
        files.each { |file| create_file_from_template(category, file) }
      end
    end
    
    private
    
    CORE_TEMPLATES = {
      auth: ['login.tsx', 'signup.tsx', 'protected-route.tsx'],
      database: ['supabase-client.ts', 'app-scoped-db.ts'],
      routing: ['app-router.tsx', 'route-config.ts'],
      core: ['package.json', 'vite.config.ts', 'index.html']
    }
  end
end
```

##### Day 3-4: Vite Build Service  
**Files to Create:**
```ruby
# /app/services/deployment/vite_builder_service.rb
module Deployment
  class ViteBuilderService
    def initialize(app)
      @app = app
    end
    
    def build!(mode = :development)
      case mode
      when :development, :preview
        FastDevelopmentBuilder.new(@app).build!  # 45s
      when :production  
        ProductionOptimizedBuilder.new(@app).build! # 3min
      end
    end
  end
end

# /app/services/deployment/fast_development_builder.rb
# /app/services/deployment/production_optimized_builder.rb
# /app/services/deployment/cloudflare_worker_optimizer.rb
```

##### Day 5: Cloudflare API Client
**Files to Create:**
```ruby
# /app/services/deployment/cloudflare_api_client.rb
module Deployment
  class CloudflareApiClient
    include HTTParty
    base_uri 'https://api.cloudflare.com/client/v4'
    
    def deploy_worker(name, script_content)
      # Deploy via API, no Wrangler CLI
    end
    
    def upload_to_r2(bucket:, key:, content:, content_type:)
      # R2 API direct upload
    end
    
    def set_worker_secrets(worker_name, app)
      # Sync AppEnvVar to Cloudflare
      app.app_env_vars.each { |env_var| sync_env_var(env_var) }
    end
  end
end
```

#### ✅ Week 1 Success Criteria
- [ ] V4 orchestrator replaces V3 successfully
- [ ] Shared templates generate foundation files
- [ ] Vite builds execute via Cloudflare Workers
- [ ] LineReplaceService and SmartSearchService integrated
- [ ] End-to-end generation works (basic test app)

---

### **Week 2: Advanced Features & Integration**
*August 19-25, 2025*

#### 🎯 Primary Goals
- Add token usage tracking
- Implement app-scoped database wrapper
- Build error recovery system
- Create comprehensive testing

#### 📋 Specific Deliverables

##### Day 1: Token Tracking Migration
**Migration to Create:**
```ruby
# /db/migrate/add_token_tracking_to_app_versions.rb
class AddTokenTrackingToAppVersions < ActiveRecord::Migration[7.0]
  def change
    add_column :app_versions, :ai_tokens_input, :integer, default: 0
    add_column :app_versions, :ai_tokens_output, :integer, default: 0  
    add_column :app_versions, :ai_cost_cents, :integer, default: 0
    add_column :ai_model_used, :string
    
    add_index :app_versions, :ai_cost_cents
    add_index :app_versions, :ai_model_used
  end
end
```

**Service Updates:**
```ruby
# Update /app/services/ai/app_builder_v4.rb
def track_usage(input_tokens, output_tokens, model)
  cost_cents = calculate_cost(input_tokens, output_tokens, model)
  
  @app_version.update!(
    ai_tokens_input: @app_version.ai_tokens_input + input_tokens,
    ai_tokens_output: @app_version.ai_tokens_output + output_tokens,
    ai_cost_cents: @app_version.ai_cost_cents + cost_cents,
    ai_model_used: model
  )
end
```

##### Day 2-3: App-Scoped Database Templates
**Template Files to Create:**
```typescript
// /app/templates/shared/database/app-scoped-db.ts
export class AppScopedDatabase {
  private appId: string;
  private supabase: SupabaseClient;
  
  constructor(supabase: SupabaseClient, appId: string) {
    this.supabase = supabase;
    this.appId = appId;
  }
  
  from(table: string) {
    const scopedTable = `app_${this.appId}_${table}`;
    console.log(`[DB] Querying table: ${scopedTable}`);
    return this.supabase.from(scopedTable);
  }
  
  getTableName(table: string): string {
    return `app_${this.appId}_${table}`;
  }
}

// /app/templates/shared/database/rls-helpers.ts  
export const createRLSPolicy = (tableName: string, appId: string) => {
  return `
    CREATE POLICY "App ${appId} isolation" ON ${tableName}
    FOR ALL USING (app_id = '${appId}');
  `;
};
```

##### Day 4: Error Recovery Enhancement ✅ IMPLEMENTED (Day 1)
**Intelligent Error Recovery via Chat Conversation:**
```ruby
# ✅ COMPLETED: /app/services/ai/app_builder_v4.rb
class AppBuilderV4
  def execute_with_retry
    # Intelligent error recovery via chat conversation
    attempt = 0
    
    begin
      attempt += 1
      execute_generation!
      
    rescue StandardError => e
      if attempt <= MAX_RETRIES
        # Instead of blind retry, ask AI to fix the error via chat
        create_error_recovery_message(e, attempt)
        sleep(2)
        retry
      else
        mark_as_failed(e)
        raise e
      end
    end
  end
  
  private
  
  def create_error_recovery_message(error, attempt)
    # Create contextual bug fix message in chat conversation
    error_context = build_error_context(error, attempt)
    
    recovery_message = @app.app_chat_messages.create!(
      role: "user",
      content: error_context,
      user: @message.user,
      # Mark as bug fix for billing purposes (tokens ignored)
      metadata: {
        type: "error_recovery",
        attempt: attempt,
        billing_ignore: true
      }.to_json
    )
    
    @message = recovery_message # Continue with recovery message
  end
  
  def build_error_context(error, attempt)
    # Builds contextual error message for AI to understand and fix
    # Includes error details, attempt info, and specific guidance
    # Based on error type (GenerationError, TimeoutError, etc.)
  end
end
```

**🎯 Key Benefits:**
- **Contextual Recovery**: AI sees full error context and can fix intelligently  
- **No Token Waste**: Bug fix messages marked `billing_ignore: true`
- **Conversation Continuity**: Uses normal chat flow, no special retry logic
- **Error-Type Specific Guidance**: Tailored instructions based on error class

##### Day 5: Comprehensive Testing & CI Integration
**V4 Unified Test Suite** (Rails CI Integration):

```ruby
# /test/integration/v4_system_test.rb - SINGLE UNIFIED TEST
class V4SystemTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  
  def setup
    @team = teams(:one)
    @user = users(:one) 
    @app = nil
  end
  
  test "V4 end-to-end app generation pipeline" do
    # This ONE test validates the entire V4 system as we build it
    
    # Phase 1: App Creation
    assert_difference 'App.count', 1 do
      @app = create_test_app("Generate a simple todo app with user authentication")
    end
    
    assert @app.persisted?
    assert_equal "generating", @app.status
    
    # Phase 2: V4 Orchestrator Execution
    perform_enqueued_jobs do
      Ai::AppBuilderV4.new(@app.app_chat_messages.first).execute!
    end
    
    @app.reload
    assert_equal "generated", @app.status
    
    # Phase 3: Validate Shared Templates Generated
    assert_v4_shared_templates_created
    
    # Phase 4: Validate App-Specific Files  
    assert_v4_app_files_created
    
    # Phase 5: Validate Vite Build Success
    assert_v4_build_successful
    
    # Phase 6: Validate Cloudflare Deployment
    assert_v4_deployment_successful
    
    # Phase 7: Validate App Functionality
    assert_v4_app_functional
    
    # Phase 8: Validate Metrics Tracking
    assert_v4_metrics_tracked
  end
  
  private
  
  def create_test_app(prompt)
    App.create!(
      name: "V4 Test App",
      prompt: prompt,
      team: @team,
      creator: @team.memberships.first,
      ai_model: 'claude-sonnet-4'
    )
  end
  
  def assert_v4_shared_templates_created
    # Test that SharedTemplateService created foundation files
    assert @app.app_files.exists?(path: 'src/lib/supabase.ts')
    assert @app.app_files.exists?(path: 'src/components/auth/AuthForm.tsx')  
    assert @app.app_files.exists?(path: 'src/pages/auth/Login.tsx')
    assert @app.app_files.exists?(path: 'package.json')
    assert @app.app_files.exists?(path: 'vite.config.ts')
  end
  
  def assert_v4_app_files_created
    # Test that AI generated app-specific files
    assert @app.app_files.exists?(path: 'src/pages/Dashboard.tsx')
    assert @app.app_files.count >= 10, "Should have at least 10 files generated"
    
    # Validate TypeScript usage
    tsx_files = @app.app_files.where("path LIKE '%.tsx'")
    assert tsx_files.count >= 5, "Should have TypeScript component files"
  end
  
  def assert_v4_build_successful
    return skip("Vite builds not implemented yet") unless defined?(Deployment::ViteBuilderService)
    
    # Test build process
    service = Deployment::ViteBuilderService.new(@app)
    result = service.build!(:development)
    
    assert result[:success], "Vite build should succeed"
    assert result[:size] < 900_000, "Worker should be under 900KB"
  end
  
  def assert_v4_deployment_successful  
    return skip("Cloudflare deployment not implemented yet") unless defined?(Deployment::CloudflareApiClient)
    
    # Test deployment via API
    assert @app.preview_url.present?, "Should have preview URL"
    assert @app.deployment_status == 'deployed'
  end
  
  def assert_v4_app_functional
    return skip("App functionality testing not implemented yet") unless @app.preview_url.present?
    
    # Test deployed app functionality (basic smoke test)
    # This would use our existing testing tools
  end
  
  def assert_v4_metrics_tracked
    version = @app.app_versions.last
    assert version.present?
    
    # Token tracking (when implemented)
    if version.respond_to?(:ai_tokens_input)
      assert version.ai_tokens_input > 0, "Should track input tokens"
      assert version.ai_cost_cents >= 0, "Should track costs"
      assert version.ai_model_used.present?, "Should track model used"
    end
    
    # File tracking
    assert version.app_version_files.count >= 10, "Should track file changes"
    assert version.display_name.present?, "Should have AI-generated display name"
  end
end
```

**Additional Component Tests:**
```ruby
# /test/services/ai/app_builder_v4_test.rb
class Ai::AppBuilderV4Test < ActiveSupport::TestCase
  test "integrates with LineReplaceService" do
    # Test surgical edits work
  end
  
  test "integrates with SmartSearchService" do  
    # Test component discovery
  end
  
  test "handles retry logic correctly" do
    # Test 2x retry system
  end
  
  test "tracks token usage per version" do
    # Test billing integration
  end
end

# /test/services/ai/shared_template_service_test.rb  
# /test/services/deployment/vite_builder_service_test.rb
# /test/services/deployment/cloudflare_api_client_test.rb
```

**CI Integration Setup:**
```bash
# Add to .github/workflows/ci.yml or equivalent
- name: Run V4 System Test
  run: rails test:integration V4SystemTest
  
# This ensures V4 functionality is validated on every commit
```

#### ✅ Week 2 Success Criteria
- [ ] **V4 Unified Test** passing in CI (validates entire pipeline)
- [ ] Token usage tracked per app version
- [ ] App-scoped database wrapper working
- [ ] Error recovery handles all edge cases
- [ ] Comprehensive test coverage (>90%)
- [ ] Performance targets met (45s dev, 3min prod builds)

**Key Benefit**: The V4SystemTest will **evolve with development** - as each service is built, the corresponding test phase "lights up" and validates that functionality. This ensures we're always rolling forward and catch regressions immediately.

---

### **Week 3: Polish & Production Readiness**
*August 26-September 1, 2025*

#### 🎯 Primary Goals
- Remove deprecated V3 code  
- Update AI_APP_STANDARDS.md
- Production deployment testing
- Documentation and migration guides

#### 📋 Specific Deliverables

##### Day 1: Cleanup & Deprecation
**Files to Remove:**
```
# Remove deprecated V3 orchestrators
/app/services/ai/app_update_orchestrator.rb
/app/services/ai/app_update_orchestrator_v2.rb
/app/services/ai/app_update_orchestrator_v3.rb (after V4 stable)

# Remove INSTANT MODE services
/app/services/deployment/fast_preview_service.rb
/app/services/deployment/cloudflare_preview_service.rb

# Remove test files
/test_*.rb
/debug_*.rb  
/check_*.rb
```

**Files to Update:**
```markdown
# /AI_APP_STANDARDS.md - Remove INSTANT MODE entirely
# Keep only PRO MODE with:
- TypeScript required
- Vite build system
- React Router structure  
- pages/components organization
- Proper build → deploy pipeline
```

##### Day 2-3: Production Testing
**Test Scripts to Create:**
```bash
# /scripts/test_v4_deployment.sh
#!/bin/bash
echo "Testing V4 deployment pipeline..."

# 1. Create test app
rails runner "
  app = App.create!(
    name: 'V4 Test App',
    prompt: 'Create a simple todo app',
    team: Team.first,
    creator: Team.first.memberships.first
  )
  puts \"Created test app: #{app.id}\"
"

# 2. Test V4 generation
# 3. Verify deployment  
# 4. Test functionality
```

**Monitoring Scripts:**
```ruby
# /app/services/monitoring/v4_health_check.rb
module Monitoring
  class V4HealthCheck
    def self.run
      # Check V4 orchestrator health
      # Verify Cloudflare API connectivity
      # Test Vite build pipeline
      # Validate template generation
    end
  end
end
```

##### Day 4: Documentation
**Docs to Create:**
```markdown
# /docs/V4_MIGRATION_GUIDE.md
# Migration from V3 to V4 for existing apps

# /docs/V4_TROUBLESHOOTING.md  
# Common issues and solutions

# /docs/V4_API_REFERENCE.md
# V4 service API documentation
```

##### Day 5: Production Rollout
**Rollout Plan:**
1. Deploy V4 to staging environment
2. Test with subset of beta users
3. Monitor metrics and performance
4. Gradual rollout to all users
5. Deprecate V3 after validation

#### ✅ Week 3 Success Criteria
- [ ] V3 code safely deprecated
- [ ] AI_APP_STANDARDS.md updated (INSTANT MODE removed)
- [ ] Production testing passes all scenarios
- [ ] Documentation complete and reviewed
- [ ] Rollout plan executed successfully

---

## 🎯 Critical Success Metrics

### Technical Performance
| Metric | Target | Measurement |
|--------|--------|-------------|
| Dev Build Time | < 45 seconds | Average build duration |
| Prod Build Time | < 3 minutes | Full optimization time |
| Worker Script Size | < 900KB | Cloudflare 1MB limit compliance |
| App Success Rate | > 95% | Working deployed apps |
| Token Usage | 90% savings | Via LineReplace integration |

### Business Impact
| Metric | Target | Measurement |
|--------|--------|-------------|
| Time to First App | < 60 seconds | User onboarding |
| App Monthly Cost | $1-2 | Supabase-first architecture |
| Development Velocity | 2x faster | vs manual development |
| API Dependencies | 0 CLI tools | Pure HTTP API approach |

---

## 🚨 Risk Mitigation

### High Risk Items
1. **Cloudflare Worker Size Limit** (1MB)
   - *Mitigation*: Hybrid asset strategy (embed critical, R2 for large)
   - *Testing*: Automated size checking in build pipeline

2. **Build Performance** (Target: 45s dev, 3min prod)
   - *Mitigation*: Fast dev mode with optimized prod mode
   - *Testing*: Performance benchmarks in CI

3. **App-Scoped Database Complexity**
   - *Mitigation*: Wrapper service with transparent debugging
   - *Testing*: Multi-tenant test scenarios

4. **Migration from V3** 
   - *Mitigation*: Parallel deployment, gradual rollout
   - *Testing*: Staging environment validation

### Low Risk Items
- Token tracking (existing database structure)
- Error recovery (proven retry patterns)
- Template system (static file approach)

---

## 🔄 Dependencies & Prerequisites

### Internal Dependencies
- [ ] LineReplaceService (existing - ready)
- [ ] SmartSearchService (existing - ready) 
- [ ] AppEnvVar model (existing - analyzed & ready)
- [ ] app_files/app_versions tables (existing - perfect for V4)

### External Dependencies
- [ ] Cloudflare API access (API token configured)
- [ ] Supabase instance (existing - ready)
- [ ] Node.js runtime for Vite builds
- [ ] Redis for caching (existing)

### Infrastructure Prerequisites
- [ ] Cloudflare Workers enabled
- [ ] R2 bucket configured
- [ ] Environment variables set
- [ ] Monitoring alerts configured

---

## 📊 Implementation Team

### Primary Developer
- **Todd Dickerson** - V4 Architecture & Implementation

### Review & Testing
- **Internal Testing** - Autonomous testing system
- **Beta Users** - Subset for production validation

### Timeline Flexibility
- **Buffer**: 1 week additional if needed
- **Minimum Viable**: Core functionality in 2 weeks
- **Full Featured**: All features in 3 weeks

---

## ✅ Go/No-Go Decision Points

### Week 1 Checkpoint
**Go Criteria:**
- [ ] V4 orchestrator basic functionality working
- [ ] Shared templates generating files
- [ ] Vite builds executing successfully
- [ ] No critical blockers identified

### Week 2 Checkpoint  
**Go Criteria:**
- [ ] Token tracking implemented
- [ ] Error recovery working reliably
- [ ] Performance targets achievable
- [ ] Test coverage adequate (>80%)

### Week 3 Production Ready
**Go Criteria:**
- [ ] All acceptance tests passing
- [ ] Performance metrics met
- [ ] Documentation complete
- [ ] Rollback plan tested

---

## 🚀 Ready for Implementation

**Status**: ✅ APPROVED FOR DEVELOPMENT

All critical decisions resolved, architecture finalized, implementation plan detailed. V4 development can begin immediately.

**Next Step**: Create first V4 orchestrator skeleton and begin Week 1 deliverables.

---

*Roadmap Created: August 11, 2025*
*Implementation Start: August 12, 2025*
*Target Completion: September 1, 2025*