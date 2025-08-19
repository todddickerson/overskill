# Web Content Fetching Implementation - August 19, 2025

## Executive Summary

Implemented a dedicated webpage content fetching tool (`os-fetch-webpage`) to complement the existing SerpAPI web search functionality. This provides AI agents with the ability to read complete webpage content, not just search snippets.

## Decision Rationale

### Why Both Tools Are Needed

1. **web_search (SerpAPI)**: 
   - Finds relevant pages across the web
   - Returns multiple results with snippets
   - Good for discovery and broad research
   - Limited to ~200 chars per result

2. **os-fetch-webpage (New Tool)**:
   - Reads COMPLETE content from specific URLs
   - Extracts main article content (removes ads/nav)
   - Returns full text (up to 100k chars)
   - Essential for deep analysis of documentation

### Use Cases That Require Full Content

- Reading API documentation pages
- Analyzing technical specifications
- Following up on search results for deeper understanding
- Processing user-provided URLs for analysis
- Extracting complete tutorials or guides
- Understanding complex implementation details

## Implementation Architecture

### 1. WebContentExtractionService
Core service for fetching and processing web content.

**Key Features:**
- Faraday HTTP client with retry logic
- Ruby-readability for article extraction
- HTML to plain text conversion
- Security filtering for malicious content
- Response size limits (5MB max)
- Content truncation at 100k chars
- Redis caching for performance

**Security Measures:**
- URL validation and blocking (no local/private IPs)
- Content sanitization (removes API keys if found)
- Integration with PromptInjectionFilter
- Maximum response size limits

### 2. WebContentTool
Agent tool wrapper for the extraction service.

**Tool Name:** `os-fetch-webpage`

**Parameters:**
- `url` (required): Complete URL to fetch
- `use_cache` (optional): Use cached content if available

**Response Format:**
```
=== Webpage Content Extracted ===
URL: https://example.com/article
Title: Article Title
Word Count: 1234
Character Count: 5678
Extracted At: 2025-08-19 14:00:00

=== Content ===
[Clean, extracted article text]
```

### 3. Integration with AppBuilderV5

Added to agent tools in two places:
1. `execute_single_tool` method - case statement
2. `fetch_webpage_content` method implementation
3. `agent-tools.json` configuration

## Technical Stack

### Required Gems (Added to Gemfile)
- `ruby-readability`: Main content extraction using Arc90's algorithm
- `html_to_plain_text`: Structured HTML to text conversion

### Already Available
- `faraday`: HTTP client (already in bundle)
- `nokogiri`: HTML parsing (already in bundle)

## Algorithm Details

### Content Extraction Pipeline
1. **Fetch**: Faraday with headers mimicking browser
2. **Extract**: Ruby-readability identifies main content
3. **Fallback**: Nokogiri-based extraction if readability fails
4. **Clean**: Remove scripts, styles, navigation, ads
5. **Convert**: HTML to structured plain text
6. **Sanitize**: Remove sensitive data, normalize whitespace
7. **Truncate**: Limit to 100k chars if needed
8. **Cache**: Store in Redis for 1 hour

### Readability Algorithm
Based on Arc90's Readability, uses multiple heuristics:
- Content density scoring
- Class/ID name analysis (article, content, post)
- Link density calculation
- Element nesting depth
- Text-to-HTML ratio

## Performance Characteristics

- **Latency**: 1-3 seconds for typical pages
- **Cache Hit**: <50ms from Redis
- **Memory**: ~5MB max per request
- **Timeout**: 20 seconds read, 10 seconds connect
- **Retry**: 2 attempts with exponential backoff

## Comparison: web_search vs os-fetch-webpage

| Feature | web_search | os-fetch-webpage |
|---------|------------|------------------|
| Purpose | Find relevant pages | Read specific page |
| Results | Multiple snippets | Single full content |
| Content Length | ~200 chars/result | Up to 100k chars |
| Speed | Fast (API call) | Slower (fetch + parse) |
| Cost | SerpAPI credits | Bandwidth only |
| Use When | Discovering info | Deep reading needed |

## Example Agent Workflow

```
User: "How do I implement authentication in Next.js 14?"

Agent Workflow:
1. web_search("Next.js 14 authentication tutorial")
   → Finds 5 relevant pages with snippets
   
2. Identifies most relevant: https://nextjs.org/docs/authentication
   
3. os-fetch-webpage("https://nextjs.org/docs/authentication")
   → Gets complete 15,000 word documentation
   
4. Analyzes full content and generates comprehensive answer
```

## Security Considerations

1. **URL Validation**: Blocks local/private IPs, file:// URLs
2. **Content Filtering**: Removes detected API keys/secrets
3. **Size Limits**: 5MB response, 100k char content
4. **Injection Protection**: Validates extracted content
5. **Rate Limiting**: Via Redis cache (1hr TTL)

## Future Enhancements

1. **JavaScript Rendering**: Add Watir/Selenium for SPAs
2. **PDF Support**: Extract text from PDF URLs
3. **Structured Data**: Extract JSON-LD, microdata
4. **Image Analysis**: Extract and describe images
5. **Video Transcripts**: Extract YouTube/video transcripts
6. **Parallel Fetching**: Batch multiple URLs
7. **Smart Summarization**: AI-powered extraction

## Testing Recommendations

### Unit Tests
```ruby
# spec/services/web_content_extraction_service_spec.rb
RSpec.describe WebContentExtractionService do
  it "extracts main content from HTML"
  it "handles malformed HTML gracefully"
  it "blocks dangerous URLs"
  it "truncates long content"
  it "uses cache when available"
end
```

### Integration Tests
```ruby
# spec/services/ai/tools/web_content_tool_spec.rb
RSpec.describe Ai::Tools::WebContentTool do
  it "fetches real webpage content"
  it "formats response correctly"
  it "handles network errors"
end
```

## Monitoring & Observability

### Key Metrics to Track
- Tool usage frequency
- Average response time
- Cache hit rate
- Error rate by domain
- Content extraction quality

### Logging
- All fetches logged with URL and result
- Errors logged with full stack trace
- Security violations logged separately

## Conclusion

The addition of `os-fetch-webpage` significantly enhances the AI agent's research capabilities by providing access to complete webpage content. Combined with `web_search`, agents can now:

1. Discover relevant information (web_search)
2. Deep-dive into specific resources (os-fetch-webpage)
3. Provide comprehensive, well-researched responses

This two-tool approach balances discovery breadth with content depth, enabling more sophisticated agent behaviors while maintaining security and performance.