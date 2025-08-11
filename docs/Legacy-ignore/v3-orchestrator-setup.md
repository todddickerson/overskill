# V3 Orchestrator Setup Guide

## Current Status

The V3 Orchestrator is fully implemented with the following features:
- ✅ Unified CREATE/UPDATE handler
- ✅ GPT-5 tool calling support  
- ✅ Real-time progress streaming
- ✅ Version tracking
- ✅ Broadcasting fixed (removed CableReady dependencies)
- ✅ Error handling improved

## Configuration Required

### 1. API Keys

You need ONE of the following configured in your `.env` file:

#### Option A: OpenAI Direct (Recommended)
```bash
OPENAI_API_KEY=sk-...your-openai-key...
```
- Full streaming support
- Native tool calling
- Better performance
- No organization verification issues

#### Option B: OpenRouter (Fallback)
```bash
OPENROUTER_API_KEY=sk-or-...your-openrouter-key...
```
- Works but may have streaming limitations
- Organization verification required for some features
- Higher latency

### 2. V3 Optimized (Always Enabled)

V3 Optimized orchestrator is now the default and only orchestrator - no configuration needed!
All apps automatically use the best and tested V3 Optimized version.

### 3. Database Setup

The following columns were added to `app_versions`:
- `status` - Track version progress
- `started_at` / `completed_at` - Timing
- `metadata` - JSONB for extra data
- `error_message` - Error tracking

Run migrations if not done:
```bash
bin/rails db:migrate
```

## Testing V3

### Quick Test
```bash
ruby test_v3_orchestrator_fresh.rb
```

### Monitor Logs
```bash
tail -f log/development.log | grep AppUpdateOrchestratorV3
```

### Run Sidekiq
```bash
bundle exec sidekiq
```

## Architecture

### Key Components

1. **AppUpdateOrchestratorV3** - Main orchestrator
   - Handles both CREATE and UPDATE
   - Manages streaming and tool calling
   - Creates versions and tracks progress

2. **ProcessAppUpdateJobV3** - Background job
   - Queues orchestrator execution
   - Handles retries

3. **StreamingBuffer** - Response buffering
   - Buffers streaming chunks
   - Broadcasts meaningful updates
   - Handles partial JSON/code blocks

4. **ProgressBroadcaster** - UI updates
   - Manages progress stages
   - Updates chat messages
   - Broadcasts to ActionCable

## API Selection Logic

```ruby
if ENV['OPENAI_API_KEY'].present?
  # Use OpenAI direct API
  @client = OpenaiGpt5Client.instance
  @use_openai_direct = true
else
  # Fall back to OpenRouter
  @client = OpenRouterClient.new
  @use_openai_direct = false
end
```

## Common Issues & Solutions

### Issue: "Organization must be verified to stream"
**Solution**: Use OpenAI direct API instead of OpenRouter

### Issue: Broadcasting errors
**Solution**: Ensure Redis is running for ActionCable
```bash
redis-server
```

### Issue: "unknown attribute 'status' for AppVersion"
**Solution**: Run migrations and restart Rails
```bash
bin/rails db:migrate
bin/rails restart
```

### Issue: Tool calls not working
**Solution**: Ensure using GPT-4o or GPT-5 model with OpenAI API

## Production Checklist

- [ ] Set `OPENAI_API_KEY` in production environment
- [ ] Run database migrations
- [ ] Ensure Redis is configured for ActionCable
- [ ] Test with a simple app generation
- [ ] Monitor logs for errors
- [ ] Check Sidekiq queue processing

## Monitoring

### Check V3 Usage
```ruby
rails console
App.joins(:app_chat_messages).where(
  app_chat_messages: { created_at: 1.day.ago.. }
).count
```

### Check Version Creation
```ruby
AppVersion.where(created_at: 1.day.ago..).pluck(:status).tally
```

### Check Errors
```ruby
AppVersion.where.not(error_message: nil).pluck(:error_message)
```