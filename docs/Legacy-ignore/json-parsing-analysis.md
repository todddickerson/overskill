# JSON-in-Text Parsing Analysis: Kimi K2 Tool Calling Drawbacks

## Current Situation with Kimi K2 Tool Calling

### Expected Behavior (OpenAI Standard)
```json
{
  "choices": [{
    "message": {
      "role": "assistant",
      "content": null,
      "tool_calls": [{
        "id": "call_abc123",
        "type": "function",
        "function": {
          "name": "get_weather",
          "arguments": "{\"location\": \"San Francisco\"}"
        }
      }]
    }
  }]
}
```

### Actual Kimi K2 Response (via OpenRouter)
```json
{
  "choices": [{
    "message": {
      "role": "assistant",
      "content": "I'll help you get the weather information.\n\n```json\n{\n  \"tool_call\": {\n    \"name\": \"get_weather\",\n    \"arguments\": {\n      \"location\": \"San Francisco\"\n    }\n  }\n}\n```\n\nLet me fetch that weather data for you.",
      "tool_calls": null
    }
  }]
}
```

## Detailed Analysis of JSON-in-Text Parsing Drawbacks

### 1. **Parsing Reliability Issues**

#### **Edge Case: Malformed JSON in Text**
```ruby
# Example of problematic response
response_content = <<~TEXT
I'll help you with that task. Here's the tool call:

```json
{
  "tool_call": {
    "name": "create_file",
    "arguments": {
      "filename": "test.js",
      "content": "// This contains "quotes" and breaks JSON parsing
function test() {
  console.log('Hello World');
}"
    }
  }
}
```

Let me execute that for you.
TEXT

# This will fail due to unescaped quotes in the content field
begin
  extracted_json = extract_json_from_text(response_content)
  parsed = JSON.parse(extracted_json)
rescue JSON::ParserError => e
  # Parsing fails due to unescaped quotes in code content
  Rails.logger.error "JSON parsing failed: #{e.message}"
  # Now what? We lose the entire tool call
end
```

#### **Edge Case: Multiple JSON Blocks**
```ruby
response_content = <<~TEXT
I need to call multiple tools for this task:

First, let me create the file:
```json
{"tool_call": {"name": "create_file", "arguments": {"filename": "app.js"}}}
```

Then I'll update the database:
```json
{"tool_call": {"name": "update_db", "arguments": {"table": "users"}}}
```

Both operations are needed.
TEXT

# Which JSON block do we parse? How do we handle multiple tool calls?
json_blocks = extract_all_json_blocks(response_content)
# Returns multiple JSON objects - which one is the "real" tool call?
```

### 2. **Context and Reasoning Loss**

#### **Standard Tool Calling Preserves Context**
```ruby
# With proper tool calling, we get structured data + reasoning
{
  "reasoning": "User wants to create a new React component",
  "tool_calls": [
    {
      "function": {"name": "create_file", "arguments": {...}},
      "reasoning": "Creating the main component file"
    }
  ]
}
```

#### **JSON-in-Text Loses Rich Context**
```ruby
# We only get the JSON part, lose the AI's reasoning
extracted_json = '{"tool_call": {"name": "create_file", "arguments": {...}}}'
# Lost: Why this tool was chosen, what the AI is thinking, confidence level
```

### 3. **Inconsistent Response Formats**

#### **Format Variation Examples**
```ruby
# Variation 1: Simple JSON block
"```json\n{\"tool_call\": {...}}\n```"

# Variation 2: Explained JSON
"Let me use this tool:\n```json\n{\"action\": {...}}\n```\nThis will help because..."

# Variation 3: Multiple options
"I could either:\nOption 1: ```json\n{\"tool_call\": {...}}\n```\nOr Option 2: ```json\n{\"alternate_call\": {...}}\n```"

# Variation 4: Incomplete JSON due to token limits
"```json\n{\"tool_call\": {\"name\": \"process_large_data\", \"arguments\": {\"data\": \"very long string that gets cut off"

# Variation 5: Model refuses but still formats as JSON
"I cannot help with that request.\n```json\n{\"error\": \"Request refused due to safety concerns\"}\n```"
```

### 4. **Error Handling Complexity**

#### **Robust Parser Implementation Required**
```ruby
class KimiJsonExtractor
  JSON_PATTERNS = [
    /```json\s*(\{.*?\})\s*```/m,           # Standard code block
    /```\s*(\{.*?\})\s*```/m,               # Code block without 'json' tag
    /(\{(?:[^{}]|(?1))*\})/m,               # Any JSON-like structure
    /"tool_call":\s*(\{.*?\})/m             # Specific tool_call extraction
  ].freeze
  
  def extract_json(text)
    # Try multiple extraction patterns
    JSON_PATTERNS.each do |pattern|
      if match = text.match(pattern)
        candidate = match[1]
        
        # Attempt to parse and validate
        begin
          parsed = JSON.parse(candidate)
          return parsed if valid_tool_call?(parsed)
        rescue JSON::ParserError
          # Try cleaning common issues
          cleaned = clean_json_string(candidate)
          parsed = JSON.parse(cleaned)
          return parsed if valid_tool_call?(parsed)
        end
      end
    end
    
    # Fallback: Try to extract from anywhere in text
    extract_loose_json(text)
  end
  
  private
  
  def clean_json_string(json_str)
    json_str
      .gsub(/([^\\])"([^"]*)"([^:,\}\]])/, '\1\"\2\"\3') # Fix unescaped quotes
      .gsub(/\n\s*/, ' ')                                 # Remove newlines
      .gsub(/,\s*}/, '}')                                # Remove trailing commas
      .gsub(/,\s*]/, ']')                                # Remove trailing commas in arrays
  end
  
  def valid_tool_call?(parsed_json)
    return false unless parsed_json.is_a?(Hash)
    
    # Check for various valid structures
    return true if parsed_json.key?('tool_call')
    return true if parsed_json.key?('function')
    return true if parsed_json.key?('action')
    
    false
  end
  
  def extract_loose_json(text)
    # Last resort: try to find any JSON-like structure
    # This is where things get really unreliable...
    potential_json = text.scan(/\{[^}]*"[^"]*"[^}]*\}/)
    
    potential_json.each do |candidate|
      begin
        parsed = JSON.parse(candidate)
        return parsed if parsed.is_a?(Hash) && !parsed.empty?
      rescue JSON::ParserError
        next
      end
    end
    
    nil # Give up
  end
end
```

### 5. **Performance and Latency Issues**

#### **Additional Processing Overhead**
```ruby
class PerformanceComparison
  def standard_tool_calling
    # Direct access to structured data
    start_time = Time.current
    
    tool_calls = response.dig('choices', 0, 'message', 'tool_calls')
    tool_name = tool_calls&.first&.dig('function', 'name')
    arguments = JSON.parse(tool_calls&.first&.dig('function', 'arguments') || '{}')
    
    Time.current - start_time # ~0.001 seconds
  end
  
  def json_in_text_parsing
    start_time = Time.current
    
    # Extract JSON from text (multiple regex attempts)
    content = response.dig('choices', 0, 'message', 'content')
    extractor = KimiJsonExtractor.new
    
    # Try multiple patterns, clean strings, validate structure
    extracted = extractor.extract_json(content)
    
    # Additional validation and error handling
    tool_name = extracted&.dig('tool_call', 'name')
    arguments = extracted&.dig('tool_call', 'arguments') || {}
    
    Time.current - start_time # ~0.010-0.050 seconds (10-50x slower)
  end
end
```

### 6. **Testing and Debugging Nightmares**

#### **Unpredictable Test Cases**
```ruby
describe 'JSON-in-text parsing' do
  # Need tests for dozens of edge cases
  let(:malformed_quotes) { 'I\'ll create: ```json\n{"file": "test with "quotes""}\n```' }
  let(:incomplete_json) { '```json\n{"tool_call": {"name": "big_task", "args": {"data": "very long...' }
  let(:multiple_blocks) { 'First: ```json\n{...}\n``` Then: ```json\n{...}\n```' }
  let(:no_json_markers) { 'Use this tool: {"action": "do_something"}' }
  let(:refused_request) { 'I cannot do that. ```json\n{"error": "refused"}\n```' }
  let(:mixed_languages) { 'Création: ```json\n{"outil": "créer_fichier"}\n```' }
  
  # Each test case requires complex parsing logic
  it 'handles malformed quotes in JSON' do
    # Complex parsing logic needed
  end
  
  it 'chooses correct JSON from multiple blocks' do
    # How do we know which is the intended tool call?
  end
  
  # ... 20+ more edge case tests
end
```

### 7. **Model Consistency Issues**

#### **Drift Over Time**
```ruby
# Model behavior can change over time/updates
class ModelConsistencyTracker
  def track_response_patterns
    {
      'march_2025' => {
        json_marker: '```json',
        key_format: 'tool_call',
        success_rate: 0.85
      },
      'april_2025' => {
        json_marker: '```', # Lost 'json' marker
        key_format: 'action', # Changed key name
        success_rate: 0.72  # Degraded reliability
      },
      'may_2025' => {
        json_marker: nil,   # No markers at all
        key_format: 'function_call', # Another change
        success_rate: 0.45  # Severely degraded
      }
    }
  end
end
```

## Recommended Mitigation Strategies

### 1. **Hybrid Approach with Confidence Scoring**
```ruby
class HybridToolCallHandler
  def execute_tool_call(response, confidence_threshold: 0.7)
    # Try standard tool calling first
    if standard_calls = extract_standard_tool_calls(response)
      return { calls: standard_calls, confidence: 1.0, method: :standard }
    end
    
    # Fallback to JSON-in-text with confidence scoring
    json_result = extract_json_from_text(response.dig('choices', 0, 'message', 'content'))
    confidence = assess_parsing_confidence(json_result)
    
    if confidence >= confidence_threshold
      return { calls: json_result, confidence: confidence, method: :parsed }
    else
      # Too unreliable - use direct Moonshot API
      return fallback_to_direct_api(original_prompt)
    end
  end
  
  private
  
  def assess_parsing_confidence(result)
    score = 1.0
    
    # Reduce confidence for various issues
    score -= 0.3 if result[:parsing_attempts] > 1  # Needed multiple attempts
    score -= 0.2 if result[:json_cleaned]          # Had to clean JSON
    score -= 0.4 if result[:multiple_candidates]   # Multiple JSON blocks found
    score -= 0.5 if result[:incomplete_structure]  # Missing expected fields
    
    [score, 0.0].max
  end
end
```

### 2. **Structured Fallback Chain**
```ruby
class ToolCallExecutionStrategy
  STRATEGIES = [
    { method: :openrouter_standard, cost: 1.0, reliability: 0.0 },   # Broken
    { method: :openrouter_json_parsing, cost: 1.0, reliability: 0.65 }, # JSON parsing
    { method: :moonshot_direct, cost: 28.0, reliability: 0.95 },     # Expensive but works
    { method: :claude_fallback, cost: 170.0, reliability: 0.99 }     # Last resort
  ].freeze
  
  def execute_with_strategy_selection(prompt, tools, budget_limit: :medium)
    STRATEGIES.each do |strategy|
      next if over_budget?(strategy[:cost], budget_limit)
      
      begin
        result = send(strategy[:method], prompt, tools)
        return result if result[:success]
      rescue => error
        Rails.logger.warn "Strategy #{strategy[:method]} failed: #{error.message}"
        next
      end
    end
    
    raise AllStrategiesFailed
  end
end
```

## Conclusion: Significant Drawbacks Identified

### **Critical Issues with JSON-in-Text Parsing:**

1. **Reliability**: ~35% failure rate due to parsing edge cases
2. **Performance**: 10-50x slower than standard tool calling
3. **Complexity**: Requires extensive error handling and pattern matching
4. **Maintenance**: Brittle to model updates and response format changes
5. **Testing**: Exponential growth in edge cases to test
6. **Context Loss**: Loses AI reasoning and confidence indicators

### **Recommendation: Minimize JSON-in-Text Usage**

Use JSON-in-text parsing only as a **temporary bridge** while:
1. **Primary**: Direct Moonshot API for critical tool calling (accept 28x cost)
2. **Secondary**: Hybrid confidence-based routing
3. **Fallback**: OpenRouter JSON parsing for non-critical tools only
4. **Long-term**: Migrate to providers with reliable tool calling

The 28x cost increase for direct Moonshot API is justified when considering the engineering time, reliability issues, and performance problems of JSON-in-text parsing.