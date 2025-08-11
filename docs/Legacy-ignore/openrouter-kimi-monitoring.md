# OpenRouter + Kimi K2 Tool Calling Monitoring System

## Overview

This system monitors the status of OpenRouter + Kimi K2 tool calling functionality and automatically switches between cost-effective OpenRouter and reliable direct Moonshot API based on real-time testing results.

## Key Benefits

- **Cost Savings**: OpenRouter is ~96% cheaper than direct Moonshot API
- **Automatic Switching**: Feature flags enable seamless provider switching
- **Reliability**: Falls back to expensive but reliable API when needed
- **Monitoring**: Regular health checks and alerting for status changes

## Architecture

### 1. Test Script (`scripts/test_openrouter_kimi_tool_calling.rb`)
- **Purpose**: Comprehensive testing of OpenRouter + Kimi K2 tool calling
- **Tests Performed**:
  - Simple tool call (weather API)
  - Multiple tools (file creation + time)
  - JSON-in-text fallback parsing
- **Output**: Detailed results with pass/fail status and recommendations

### 2. Provider Selector (`app/services/ai/provider_selector_service.rb`)
- **Purpose**: Intelligently select AI provider based on capabilities and cost
- **Logic**:
  - Check feature flags for OpenRouter tool calling status
  - Verify recent test results (last 7 days)
  - Route to cheapest working provider
- **Cost Matrix**:
  - OpenRouter: 1x (base cost)
  - Moonshot Direct: 28x
  - Claude Sonnet: 170x (vision only)

### 3. Smart Request Handler (`app/services/ai/smart_request_handler.rb`)
- **Purpose**: Execute requests with automatic fallback chains
- **Features**:
  - Provider-specific implementations
  - JSON-in-text parsing fallback for OpenRouter
  - Cost tracking and metrics
  - Automatic fallback on failures

### 4. Feature Flags (`app/models/feature_flag.rb`)
- **Purpose**: Control provider routing with gradual rollouts
- **Features**:
  - Boolean enable/disable
  - Percentage-based rollouts (10%, 50%, 100%)
  - User-specific targeting
  - Admin interface via Avo

### 5. Health Check Tasks (`lib/tasks/ai_provider_health_check.rake`)
- **Purpose**: Automated monitoring and alerting
- **Commands**:
  - `rake ai:health_check` - Run full test suite and update flags
  - `rake ai:provider_status` - Show current status
  - `rake ai:enable_openrouter_tool_calling` - Manual override
  - `rake ai:disable_openrouter_tool_calling` - Manual override

## Usage Examples

### Manual Testing
```bash
# Run comprehensive tool calling test
ruby scripts/test_openrouter_kimi_tool_calling.rb

# Check current provider status
rake ai:provider_status

# Run health check and update feature flags
rake ai:health_check
```

### Code Integration
```ruby
# Use smart request handler (automatically selects best provider)
result = Ai::SmartRequestHandler.handle_tool_calling_request(
  "Create a file called test.js with Hello World content",
  available_tools,
  user: current_user
)

# Check if OpenRouter tool calling is available
if Ai::ProviderSelectorService.tool_calling_available_via_openrouter?
  # Use cheap OpenRouter
else
  # Use expensive but reliable Moonshot
end
```

### Feature Flag Management
```ruby
# Create/update feature flag
FeatureFlag.create!(
  name: 'openrouter_kimi_tool_calling',
  enabled: true,
  percentage: 10,  # Start with 10% rollout
  description: 'Enable OpenRouter for Kimi K2 tool calling'
)

# Check if enabled for specific user
if FeatureFlag.enabled?('openrouter_kimi_tool_calling', user_id: user.id)
  # User is in the rollout group
end
```

## Cost Impact Analysis

### Current Costs (Direct Moonshot API)
- Input: $0.15 per 1M tokens
- Output: $2.50 per 1M tokens
- **Example**: 5K input + 2K output = $0.0058 per request

### With OpenRouter (when working)
- Input: $0.088 per 1M tokens  
- Output: $0.088 per 1M tokens
- **Example**: 5K input + 2K output = $0.0006 per request
- **Savings**: ~90% cost reduction

### Monthly Impact (1000 tool calling requests)
- Direct Moonshot: ~$170/month
- OpenRouter: ~$18/month
- **Potential Savings**: $152/month (~$1,800/year)

## Monitoring and Alerting

### Automated Health Checks
- **Frequency**: Daily via cron job
- **Trigger**: `rake ai:health_check`
- **Actions**:
  - Run test suite
  - Update feature flags
  - Send alerts on status changes
  - Log results for analysis

### Status Change Alerts
When tool calling status changes:
- ✅ **Working**: "OpenRouter + Kimi K2 tool calling is now WORKING! Consider gradual rollout."
- ❌ **Broken**: "OpenRouter + Kimi K2 tool calling has STOPPED working. Falling back to direct API."

### Metrics Tracked
- Success/failure rates by provider
- Response times
- Cost per request
- Feature flag rollout percentages
- Test result history

## Deployment Strategy

### Phase 1: Setup (Completed)
- ✅ Create test script and monitoring infrastructure
- ✅ Implement feature flags and provider selection
- ✅ Set up health check tasks

### Phase 2: Initial Testing
- [ ] Run daily health checks for 1 week
- [ ] Verify OpenRouter tool calling is still broken
- [ ] Confirm fallback to Moonshot API works

### Phase 3: Gradual Rollout (When OpenRouter works)
- [ ] Enable for 10% of users initially
- [ ] Monitor for 48 hours
- [ ] Increase to 50% if successful
- [ ] Full rollout to 100% after validation

### Phase 4: Ongoing Monitoring
- [ ] Daily automated health checks
- [ ] Weekly cost analysis reports
- [ ] Quarterly review of provider alternatives

## Troubleshooting

### Common Issues

**Test Script Fails**
```bash
# Check API keys
echo $OPENROUTER_API_KEY

# Verify network connectivity
curl -H "Authorization: Bearer $OPENROUTER_API_KEY" https://openrouter.ai/api/v1/models

# Run with verbose logging
VERBOSE_AI_LOGGING=true ruby scripts/test_openrouter_kimi_tool_calling.rb
```

**Feature Flag Not Working**
```ruby
# Check flag exists and is enabled
flag = FeatureFlag.find_by(name: 'openrouter_kimi_tool_calling')
puts flag.inspect

# Check percentage rollout
puts "User in rollout: #{FeatureFlag.enabled?('openrouter_kimi_tool_calling', user_id: 123)}"
```

**High Costs Continue**
```bash
# Check which provider is being used
rake ai:provider_status

# Verify recent test results
ls -la log/tool_calling_tests/

# Manual disable if needed
rake ai:disable_openrouter_tool_calling
```

## Future Enhancements

### Planned Improvements
- **A/B Testing**: Compare quality between providers
- **Cost Budgets**: Hard limits on expensive API usage
- **Multi-Region**: Test different OpenRouter endpoints
- **Quality Metrics**: Track success rates by request type

### Alternative Providers
Monitor and potentially integrate:
- **Groq**: Fast inference, competitive pricing
- **Together AI**: Open source models
- **Replicate**: Model variety and flexibility
- **Direct Moonshot**: When they improve pricing

This monitoring system ensures OverSkill can quickly capitalize on cost savings when OpenRouter + Kimi K2 tool calling becomes reliable, while maintaining current functionality through intelligent fallbacks.