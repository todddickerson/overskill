# Deprecated App Generators and Orchestrators

**DEPRECATED as of August 11, 2025**

All these generators and orchestrators have been superseded by the **AppUpdateOrchestratorV3Optimized** which provides:

- ✅ 50-80% faster generation with OpenAI prompt caching
- ✅ System-level prompts with full standards
- ✅ Proper streaming support 
- ✅ Instant Cloudflare Workers deployment
- ✅ Dual AI model support (GPT-5 and Claude Sonnet 4)
- ✅ Comprehensive error handling
- ✅ Real-time UI updates via ActionCable

## Files Moved Here:

### Original Orchestrators:
- `app_update_orchestrator.rb` - The original orchestrator
- `app_update_orchestrator_v2.rb` - V2 with enhanced features
- `app_update_orchestrator_v3.rb` - Original V3 (had timeout issues)
- `app_update_orchestrator_streaming.rb` - Streaming variant
- `app_update_orchestrator_fallback.rb` - Fallback version
- `app_update_orchestrator_v3_claude.rb` - Claude variant

### Generator Services:
- `app_generator_service.rb` - Original generator service
- `simple_app_generator.rb` - Simplified generator
- `enhanced_app_generator.rb` - Enhanced generator
- `structured_app_generator.rb` - Structured generation without function calling
- `lovable_style_generator.rb` - Lovable.dev style generator
- `unified_ai_coordinator.rb` - Coordination service

### Background Jobs:
- `process_app_update_job.rb` - Original job processor (replaced by V3)
- `process_app_update_job_v2.rb` - V2 job processor

## What To Use Instead:

**For all app generation and updates:**
```ruby
# Use the V3 Optimized orchestrator directly
message = app.app_chat_messages.create!(...)
orchestrator = Ai::AppUpdateOrchestratorV3Optimized.new(message)
orchestrator.execute!

# Or via the V3 job (automatically uses optimized version)
ProcessAppUpdateJobV3.perform_later(message)
```

**Configuration:**
- No more environment variable switching
- V3 Optimized is always used
- Supports both GPT-5 and Claude Sonnet 4 via `app.ai_model`

## Migration Notes:

All existing functionality has been consolidated into the V3 Optimized version:
- File generation ✅
- Real-time progress updates ✅  
- Streaming support ✅
- Deployment integration ✅
- Error handling ✅
- Multiple AI models ✅

**DO NOT** restore these files - they contain outdated patterns and cause:
- Context size issues leading to timeouts
- Inefficient prompt management  
- Incomplete deployment integration
- Poor error handling
- Fragmented codebase maintenance