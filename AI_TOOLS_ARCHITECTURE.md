# AI Tools Architecture - August 19, 2025

## Executive Summary

Implemented a comprehensive three-tier web research strategy with Perplexity integration and refactored all AI tool implementations into a centralized service for better maintainability.

## Architecture Changes

### 1. Centralized Tool Service (NEW)

**Location**: `app/services/ai/ai_tool_service.rb`

All tool implementations have been extracted from `AppBuilderV5` into a dedicated service:
- **File Management**: write, read, delete, rename files
- **Search**: file search with regex patterns
- **Web Research**: SerpAPI search, webpage fetching, Perplexity research
- **Package Management**: add/remove dependencies
- **Image Generation**: create and edit images
- **Utilities**: download files, read logs, analytics

**Benefits**:
- AppBuilderV5 focuses purely on orchestration
- Tool implementations are reusable across services
- Easier testing and maintenance
- Clear separation of concerns

### 2. AppBuilderV5 Refactoring

**Location**: `app/services/ai/app_builder_v5.rb`

Now delegates all tool calls to `AiToolService`:
```ruby
# Before (1000+ lines of tool implementations)
def write_file(path, content)
  # Complex implementation...
end

# After (clean delegation)
@tool_service.write_file(path, content)
```

## Three-Tier Web Research Strategy

### Tool Comparison Matrix

| Feature | web_search | os-fetch-webpage | perplexity-research |
|---------|------------|------------------|---------------------|
| **Purpose** | Find relevant pages | Read specific URL | AI-powered research |
| **Results** | Multiple snippets (~200 chars) | Full content (100k chars) | AI synthesis with citations |
| **Sources** | 5-10 pages | Single URL | 20+ sources automatically |
| **Speed** | Fast (<1s) | Medium (1-3s) | Slow (3-5s) |
| **Cost** | Low (SerpAPI) | Minimal (bandwidth) | HIGH ($0.10/query) |
| **Best For** | Discovery | Deep reading | Complex research |

### When to Use Each Tool

#### 1. web_search (SerpAPI)
```json
{
  "name": "web_search",
  "when": [
    "Finding multiple relevant pages",
    "Quick overview from snippets",
    "Discovery phase of research",
    "Finding specific content types (news, GitHub, PDFs)",
    "Getting real images"
  ],
  "cost": "$0.001 per search"
}
```

#### 2. os-fetch-webpage (Traditional Scraping)
```json
{
  "name": "os-fetch-webpage",
  "when": [
    "Reading complete documentation",
    "User provides specific URL",
    "Need exact content without AI interpretation",
    "Following up on search results",
    "Cost-sensitive operations"
  ],
  "cost": "Bandwidth only"
}
```

#### 3. perplexity-research (AI Synthesis)
```json
{
  "name": "perplexity-research",
  "when": [
    "Complex research questions",
    "Need current information with citations",
    "Fact-checking claims",
    "Multi-source synthesis required",
    "Chain-of-thought reasoning needed"
  ],
  "cost": "$0.10+ per query (30-40x traditional methods)",
  "modes": {
    "quick": "Fast facts with sonar model",
    "research": "Comprehensive with sonar-pro",
    "deep": "Multi-query deep research",
    "fact_check": "Verify statements with citations"
  }
}
```

## Cost Analysis

### Perplexity Hidden Costs Warning ⚠️
- Each query retrieves ~20 citations
- Citations count as input tokens (multiplies cost by 20x)
- Can cost $0.10 per query vs $0.003 for direct OpenAI
- 30-40x more expensive than traditional methods

### Cost Optimization Strategy
1. **Default**: Use web_search for discovery
2. **Deep Dive**: Use os-fetch-webpage for specific pages
3. **Premium**: Use perplexity-research only when AI synthesis is essential

## Implementation Details

### PerplexityContentService
```ruby
# Features:
- Multiple AI models (sonar, sonar-pro, deep-research)
- Redis caching (1 hour TTL)
- Cost tracking and estimation
- URL vs topic detection
- Fact-checking mode
```

### WebContentExtractionService
```ruby
# Features:
- Ruby-readability for article extraction
- Security filtering (blocks local IPs)
- Content sanitization (removes API keys)
- 100k character limit
- Redis caching
```

### AiToolService
```ruby
# Centralized tool implementations:
- All file operations
- Web research (3 tools)
- Package management
- Image generation
- Search functionality
```

## Testing Coverage

### Test Files Created
1. `test/services/ai/ai_tool_service_test.rb`
   - File management operations
   - Package dependency management
   - Web research tools
   - Image generation

2. `test/services/perplexity_content_service_test.rb`
   - API integration
   - Caching behavior
   - Cost calculations
   - Error handling

3. `test/services/web_content_extraction_service_test.rb`
   - URL validation and security
   - HTML extraction
   - Content sanitization
   - Cache management

## Security Considerations

### URL Validation
- Blocks localhost, 127.0.0.1, private IPs
- Blocks file:// protocol
- Validates URL format

### Content Sanitization
- Removes detected API keys
- Filters sensitive patterns
- Integration with PromptInjectionFilter

### Rate Limiting
- Redis cache prevents excessive API calls
- 1-hour TTL for cached content
- Cost monitoring and alerts

## Migration Guide

### For Developers
1. Tool implementations are now in `AiToolService`
2. AppBuilderV5 delegates to tool service
3. Add new tools to AiToolService, not AppBuilderV5
4. Update agent-tools.json for new tools

### For Adding New Tools
```ruby
# 1. Add to AiToolService
def new_tool(args)
  # Implementation
end

# 2. Add to agent-tools.json
{
  "name": "new-tool",
  "description": "Clear description with WHEN/ADVANTAGES/LIMITATIONS/COST",
  "parameters": {...}
}

# 3. Add delegation in AppBuilderV5
when 'new-tool'
  @tool_service.new_tool(tool_args)

# 4. Add tests
test "new_tool does something" do
  # Test implementation
end
```

## Performance Metrics

### Response Times
- web_search: ~500ms
- os-fetch-webpage: 1-3s (cached: <50ms)
- perplexity-research: 3-5s (cached: <50ms)

### Token Usage
- web_search: N/A (API call only)
- os-fetch-webpage: N/A (bandwidth only)
- perplexity-research: 2000-4000 tokens typical

## Future Enhancements

1. **JavaScript Rendering**: Add Selenium for SPAs
2. **PDF Support**: Extract text from PDF URLs
3. **Structured Data**: Extract JSON-LD, microdata
4. **Parallel Fetching**: Batch multiple URLs
5. **Smart Caching**: Intelligent cache invalidation
6. **Cost Optimization**: Automatic tool selection based on budget

## Monitoring & Observability

### Key Metrics to Track
- Tool usage frequency by type
- Average response times
- Cache hit rates
- Error rates by tool
- Cost per research task
- Token usage trends

### Logging
```ruby
Rails.logger.info "[AiToolService] Tool executed: #{tool_name}"
Rails.logger.info "[Perplexity] Token usage: #{tokens}, Cost: $#{cost}"
Rails.logger.info "[WebContent] Cache hit for: #{url}"
```

## Conclusion

The refactored architecture provides:
1. **Cleaner Code**: Centralized tool implementations
2. **Better Testing**: Comprehensive test coverage
3. **Cost Control**: Clear pricing visibility
4. **Flexibility**: Three-tier research strategy
5. **Maintainability**: Separation of concerns

Choose the right tool for each research need:
- **Breadth**: web_search
- **Depth**: os-fetch-webpage  
- **Intelligence**: perplexity-research