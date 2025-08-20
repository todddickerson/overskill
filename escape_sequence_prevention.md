# Escape Sequence Prevention Measures

## Problem Summary
The AI (especially when using line-replace operations) was generating malformed import statements with literal `\n` characters instead of actual newlines, causing build failures like:
- `ERROR: Unterminated regular expression` 
- `ERROR: Syntax error "n"`

## Root Causes
1. **AI Response Formatting**: LLMs sometimes include escape sequences in their responses when they should provide raw content
2. **Line Replace Operations**: When AI adds imports, it may incorrectly join multiple lines with `\n` instead of actual newlines
3. **JSON Parsing**: Tool arguments containing code might get double-escaped

## Prevention Measures Implemented

### 1. Input Sanitization in AiToolService
Added `clean_escaped_content` method that:
- Detects improperly escaped content in write_file and line_replace operations
- Intelligently distinguishes between code and non-code content
- Converts literal `\n` to actual newlines in import statements
- Fixes escaped quotes that aren't inside strings
- Logs warnings when cleaning is performed

### 2. Validation Rules
The cleaner checks for:
- Import/export statements (TypeScript/JavaScript)
- Const/let/var declarations
- Function/class definitions
- Distinguishes intentional JSON escaping from malformed code

### 3. Safe Processing
- Preserves intentional escape sequences in strings (e.g., `"\\n"` in JSON)
- Only processes content that looks like code
- Conservative approach for non-code content

## Code Changes

### /app/services/ai/ai_tool_service.rb

```ruby
# Added to write_file method
if content && (content.include?('\\n') || content.include?('\\"'))
  original_content = content
  content = clean_escaped_content(content)
  if content != original_content
    @logger.warn "[AiToolService] Cleaned escape sequences in content for #{file_path}"
  end
end

# Added to replace_file_content method  
if replacement && (replacement.include?('\\n') || replacement.include?('\\"'))
  original_replacement = replacement
  replacement = clean_escaped_content(replacement)
  if replacement != original_replacement
    @logger.warn "[AiToolService] Cleaned escape sequences in replacement for #{file_path}"
  end
end

# New private method
def clean_escaped_content(content)
  # Intelligent cleaning based on content type
  # See implementation in ai_tool_service.rb
end
```

## Testing
After implementing these measures:
- ✅ Successfully fixed malformed imports in HeroSection.tsx
- ✅ Successfully fixed malformed imports in AboutSection.tsx  
- ✅ Cleaned chart.tsx escape sequences
- ✅ Deployment successful with all fixes

## Monitoring
Watch for these log messages:
- `[AiToolService] Cleaned escape sequences in content for [file]`
- `[AiToolService] Cleaned escape sequences in replacement for [file]`

These indicate the prevention system is working and catching issues before they cause build failures.

## Future Improvements
1. Add metrics to track how often cleaning is needed
2. Analyze patterns to improve AI prompting
3. Consider adding a pre-build validation step
4. Add unit tests for the clean_escaped_content method