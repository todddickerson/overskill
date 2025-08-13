# V5 Blockers and Required Fixes

## Critical Issues Blocking V5 Test Generation

### 1. ❌ AnthropicClient Singleton Usage
**Location**: `app/services/ai/app_builder_v5.rb:402`
```ruby
# CURRENT (WRONG):
client = AnthropicClient.new

# SHOULD BE:
client = Ai::AnthropicClient.instance
```

### 2. ❌ Model Name Format
**Location**: `app/services/ai/app_builder_v5.rb:408`
```ruby
# CURRENT (WRONG):
model: "claude_opus_4_1"

# SHOULD BE:
model: :claude_opus_4  # Symbol, not string
```

### 3. ❌ Missing Prompt Classes
**Location**: `app/services/ai/app_builder_v5.rb`
The AgentPrompt and AgentTools classes referenced by AgentPromptService don't exist:
```ruby
# Line 15-16 in agent_prompt_service.rb:
@prompt_generator = AgentPrompt.new(@variables)  # Class doesn't exist
@tools_generator = AgentTools.new(@variables)    # Class doesn't exist
```

### 4. ❌ Stub Implementations
Several critical methods are just stubs returning empty/placeholder data:

#### `generate_file_content` (line 536)
```ruby
def generate_file_content(tool, template_path)
  # Generate file content based on tool and template
  ""  # Returns empty string!
end
```

#### `extract_implementation_plan` (line 531)
```ruby
def extract_implementation_plan(response)
  # Extract structured plan from AI response
  { steps: [], components: [], integrations: [] }  # Empty plan!
end
```

### 5. ⚠️ Tool Execution with Claude
The `call_ai_with_context` method passes tools but doesn't handle tool responses:
```ruby
response = client.chat(
  messages: messages,
  model: :claude_opus_4,
  tools: @prompt_service.generate_tools  # Tools passed but responses not processed
)
```
Need to use `chat_with_tools` instead and process tool calls.

### 6. ⚠️ Create App Logic
The `create_app` method needs to check if app already exists on the chat_message:
```ruby
def create_app
  return @chat_message.app if @chat_message.app.present?
  # ... create new app
end
```

## Quick Fixes Needed

```ruby
# 1. Fix AnthropicClient usage
def call_ai_with_context(prompt)
  client = Ai::AnthropicClient.instance  # Fix: Use singleton
  
  messages = build_messages_with_context(prompt)
  
  # Fix: Use chat_with_tools for tool support
  response = client.chat_with_tools(
    messages,
    @prompt_service.generate_tools,
    model: :claude_opus_4,  # Fix: Use symbol
    use_cache: true,        # Enable prompt caching!
    temperature: 0.7
  )
  
  # Process tool calls if present
  if response[:tool_calls].present?
    process_tool_calls(response[:tool_calls])
  end
  
  response
end

# 2. Implement actual file generation
def generate_file_content(tool, template_path)
  # Read template if exists
  template_file = File.join(template_path, tool[:file_path])
  base_content = File.exist?(template_file) ? File.read(template_file) : ""
  
  # Use AI to enhance/modify based on requirements
  prompt = "Generate content for #{tool[:file_path]} based on: #{tool[:description]}"
  
  response = call_ai_with_context(prompt)
  response[:content] || base_content
end
```

## Missing AgentPrompt and AgentTools Classes

Need to create these or modify AgentPromptService to work without them:

```ruby
# Option 1: Create simple wrapper classes
class AgentPrompt
  def initialize(variables)
    @variables = variables
  end
  
  def generate
    template = File.read(Rails.root.join('app/services/ai/prompts/agent-prompt.txt'))
    @variables.each do |key, value|
      template.gsub!("{{#{key}}}", value.to_s)
    end
    template
  end
end

class AgentTools
  def initialize(variables)
    @variables = variables
  end
  
  def parsed_config
    tools_json = File.read(Rails.root.join('app/services/ai/prompts/agent-tools.json'))
    tools = JSON.parse(tools_json)
    # Replace variables in tools
    tools
  end
  
  def tool_names
    parsed_config.map { |t| t['name'] }
  end
end
```

## Test Flow

Once these fixes are applied:

1. **Start Rails Console**:
```ruby
rails console
```

2. **Create Test User & App**:
```ruby
user = User.first || User.create!(email: "test@example.com", password: "password")
team = user.teams.first || user.teams.create!(name: "Test Team")
membership = team.memberships.first
```

3. **Create Chat Message**:
```ruby
message = AppChatMessage.create!(
  user: user,
  role: 'user',
  content: 'Create a simple todo app with add, complete, and delete functionality'
)
```

4. **Trigger V5 Builder**:
```ruby
ProcessAppUpdateJobV4.perform_now(message)
```

5. **Monitor Progress**:
```ruby
# Watch the assistant message update
assistant = AppChatMessage.where(role: 'assistant').last
assistant.reload
assistant.loop_messages
assistant.tool_calls
assistant.thinking_status
```

## Environment Variables Confirmed ✅
- `ANTHROPIC_API_KEY` ✅ Set
- `OPENAI_API_KEY` ✅ Set (for fallback)
- `SUPABASE_*` ✅ All configured
- `CLOUDFLARE_*` ✅ All configured

## Summary

**Main Blockers**:
1. AnthropicClient singleton usage (easy fix)
2. Missing AgentPrompt/AgentTools classes (need to create)
3. Stub implementations for file generation (need real implementation)

**Estimated Time to Fix**: 30-60 minutes

Once these are fixed, the V5 agent loop should work end-to-end with the simplified save-and-broadcast UI pattern.