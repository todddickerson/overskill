# TypeScript Template Configuration Issues & Solutions

## Root Cause Analysis

The TypeScript build failures are caused by misconfigured templates in `/app/services/ai/templates/overskill_20250728/`:

### Issue 1: Missing TypeScript Path Mapping
**File**: `tsconfig.json`
**Problem**: Has no `paths` configuration to match Vite's `@` alias
**Impact**: TypeScript cannot resolve `@/components/...` imports during build

### Issue 2: Missing Composite Configuration  
**File**: `tsconfig.node.json`
**Problem**: Missing `"composite": true` required for project references
**Impact**: TypeScript fails when building with references

### Issue 3: No Build-Time Validation
**Problem**: Apps are generated and saved without build validation
**Impact**: Broken apps make it to deployment stage

---

## Immediate Fixes Required

### 1. Fix Template tsconfig.json
```json
{
  "compilerOptions": {
    "target": "ES2020",
    "useDefineForClassFields": true,
    "lib": ["ES2020", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "skipLibCheck": true,
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": true,
    "jsx": "react-jsx",
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noFallthroughCasesInSwitch": true,
    "baseUrl": ".",
    "paths": {
      "@/*": ["./src/*"]
    }
  },
  "include": ["src"],
  "references": [{ "path": "./tsconfig.node.json" }]
}
```

### 2. Fix Template tsconfig.node.json
```json
{
  "compilerOptions": {
    "composite": true,
    "target": "ES2022",
    "lib": ["ES2023"],
    "module": "ESNext",
    "skipLibCheck": true,
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "moduleDetection": "force",
    "noEmit": false,
    "types": ["node"],
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noFallthroughCasesInSwitch": true
  },
  "include": ["vite.config.ts"]
}
```

---

## Self-Healing Build System Implementation

### Architecture Components

#### 1. BuildErrorAnalyzer Service
- Parses TypeScript/Vite build errors
- Categorizes errors by type (missing modules, config issues, etc.)
- Generates AI-friendly fix instructions
- Already implemented at: `app/services/ai/build_error_analyzer.rb`

#### 2. SelfHealingBuildService
```ruby
module Deployment
  class SelfHealingBuildService
    MAX_RETRY_ATTEMPTS = 2
    
    def initialize(app)
      @app = app
      @attempt = 0
    end
    
    def build_with_retry!
      loop do
        @attempt += 1
        Rails.logger.info "[SelfHealing] Build attempt #{@attempt}/#{MAX_RETRY_ATTEMPTS}"
        
        # Try to build
        result = Deployment::ViteBuildService.new(@app).build_app!
        
        if result[:success]
          Rails.logger.info "[SelfHealing] Build succeeded on attempt #{@attempt}"
          return result
        end
        
        # If we've exhausted retries, fail
        if @attempt >= MAX_RETRY_ATTEMPTS
          Rails.logger.error "[SelfHealing] Build failed after #{@attempt} attempts"
          return result
        end
        
        # Analyze errors and attempt fix
        Rails.logger.info "[SelfHealing] Analyzing build errors..."
        fix_result = analyze_and_fix_errors(result[:error])
        
        unless fix_result[:success]
          Rails.logger.error "[SelfHealing] Could not generate fixes"
          return result
        end
        
        Rails.logger.info "[SelfHealing] Applied #{fix_result[:fixes_applied]} fixes, retrying build..."
      end
    end
    
    private
    
    def analyze_and_fix_errors(error_output)
      # Analyze errors
      analyzer = Ai::BuildErrorAnalyzer.new(error_output)
      analysis = analyzer.analyze
      
      unless analysis[:can_auto_fix]
        return { success: false, reason: "Errors cannot be auto-fixed" }
      end
      
      # Send to AI for fixes
      ai_service = Ai::BuildFixerService.new(@app)
      fixes = ai_service.generate_fixes(analysis[:ai_prompt])
      
      # Apply fixes
      fixes_applied = 0
      fixes.each do |fix|
        if apply_fix(fix)
          fixes_applied += 1
        end
      end
      
      { success: fixes_applied > 0, fixes_applied: fixes_applied }
    end
    
    def apply_fix(fix)
      case fix[:type]
      when 'update_config'
        update_config_file(fix[:file], fix[:changes])
      when 'add_dependency'
        add_npm_dependency(fix[:package])
      when 'create_file'
        create_missing_file(fix[:path], fix[:content])
      else
        false
      end
    end
  end
end
```

#### 3. BuildFixerService (AI Integration)
```ruby
module Ai
  class BuildFixerService
    def initialize(app)
      @app = app
      @client = OpenaiClient.new
    end
    
    def generate_fixes(error_analysis)
      prompt = build_fix_prompt(error_analysis)
      
      response = @client.chat(
        messages: [
          {
            role: "system",
            content: "You are a TypeScript/React build error fixer. Generate JSON fixes only."
          },
          {
            role: "user",
            content: prompt
          }
        ],
        model: "gpt-4-turbo-preview",
        response_format: { type: "json_object" }
      )
      
      parse_fix_response(response)
    end
    
    private
    
    def build_fix_prompt(analysis)
      <<~PROMPT
        Fix these TypeScript build errors for a React app.
        
        #{analysis}
        
        Generate fixes in this JSON format:
        {
          "fixes": [
            {
              "type": "update_config",
              "file": "tsconfig.json",
              "changes": { ... }
            },
            {
              "type": "add_dependency",
              "package": "package-name"
            }
          ]
        }
        
        Only include fixes that will resolve the errors.
      PROMPT
    end
  end
end
```

---

## Integration with AppBuilderV5

### Add Build Validation Before Deployment
```ruby
# In app_builder_v5.rb
def execute!
  # ... existing generation code ...
  
  # NEW: Validate build before marking complete
  if should_validate_build?
    validation_result = validate_build
    unless validation_result[:success]
      # Send errors back to AI for fixes
      fix_result = request_ai_fixes(validation_result[:errors])
      if fix_result[:success]
        apply_fixes(fix_result[:fixes])
        # Re-validate after fixes
        validation_result = validate_build
      end
    end
  end
  
  # ... continue with deployment ...
end

private

def validate_build
  # Quick TypeScript check without full build
  validator = Ai::TypeScriptValidator.new(@app)
  validator.check_types
end

def request_ai_fixes(errors)
  prompt = <<~PROMPT
    The TypeScript build validation failed with these errors:
    
    #{errors}
    
    Please fix these errors using the os-write or os-line-replace tools.
    Focus on configuration issues first (tsconfig.json, missing dependencies).
  PROMPT
  
  # Send back through the same AI conversation
  process_agent_request(prompt)
end
```

---

## Prevention Strategies

### 1. Template Validation CI
Add tests to ensure templates always build successfully:
```ruby
# test/services/ai/template_validation_test.rb
class TemplateValidationTest < ActiveSupport::TestCase
  test "base template builds without errors" do
    # Copy template to temp directory
    # Run TypeScript check
    # Assert no errors
  end
  
  test "template has proper TypeScript paths config" do
    tsconfig = JSON.parse(read_template_file("tsconfig.json"))
    assert tsconfig["compilerOptions"]["paths"]
    assert_equal ["./src/*"], tsconfig["compilerOptions"]["paths"]["@/*"]
  end
end
```

### 2. Pre-Generation Validation
Check templates before AI uses them:
```ruby
class BaseContextService
  def validate_template!
    errors = []
    
    # Check tsconfig.json
    tsconfig = JSON.parse(read_template("tsconfig.json"))
    unless tsconfig.dig("compilerOptions", "paths", "@/*")
      errors << "tsconfig.json missing TypeScript paths for @ alias"
    end
    
    # Check tsconfig.node.json
    tsconfig_node = JSON.parse(read_template("tsconfig.node.json"))
    unless tsconfig_node.dig("compilerOptions", "composite") == true
      errors << "tsconfig.node.json missing composite: true"
    end
    
    raise "Template validation failed: #{errors.join(', ')}" if errors.any?
  end
end
```

### 3. Build-Time Metrics
Track build success rates:
```ruby
class BuildMetrics
  def self.record_build(app, success, errors = nil)
    metric = BuildMetric.create!(
      app: app,
      success: success,
      error_summary: errors&.first(500),
      attempted_at: Time.current
    )
    
    # Alert if failure rate is high
    recent_failures = BuildMetric.where(created_at: 1.hour.ago..)
                                 .where(success: false).count
    if recent_failures > 5
      AlertService.notify("High build failure rate: #{recent_failures} in last hour")
    end
  end
end
```

---

## Implementation Priority

1. **Immediate** (Day 1):
   - Fix template files (tsconfig.json, tsconfig.node.json)
   - Deploy fixed templates

2. **Short-term** (Week 1):
   - Implement BuildErrorAnalyzer
   - Add basic retry mechanism

3. **Medium-term** (Week 2-3):
   - Full self-healing system
   - AI-powered fix generation
   - Build validation in AppBuilderV5

4. **Long-term** (Month 1):
   - Comprehensive template testing
   - Build metrics dashboard
   - Predictive error prevention

---

## Expected Outcomes

- **90% reduction** in build failures
- **Automatic recovery** from common TypeScript errors
- **No broken apps** reaching deployment
- **Faster iteration** with self-fixing builds
- **Better developer experience** with clear error messages

---

## Next Steps

1. Apply template fixes immediately
2. Test with Pageforge app (ID: 1027)
3. Roll out self-healing to all new generations
4. Monitor success metrics
5. Iterate based on failure patterns