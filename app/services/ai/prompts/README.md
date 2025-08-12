# AI Agent Prompt System

This system provides a flexible way to generate AI agent prompts and tool configurations with dynamic variable substitution.

## Overview

The system consists of three main components:

1. **AgentPrompt** - Handles the main system prompt template
2. **AgentTools** - Handles the tools configuration JSON
3. **AgentPromptService** - Unified interface for both

## Basic Usage

### Simple Generation

```ruby
# Use default OverSkill configuration
service = AI::Prompts::AgentPromptService.new
config = service.generate_config

# Access individual parts
prompt = service.generate_prompt
tools = service.generate_tools
tool_names = service.tool_names
```

### Custom Variables

```ruby
# Override specific variables
service = AI::Prompts::AgentPromptService.new(
  platform_name: "MyPlatform",
  tool_prefix: "mp-",
  backend_integration: "Firebase"
)

prompt = service.generate_prompt
# Prompt will contain "MyPlatform" instead of "OverSkill"
```

### Platform-Specific Configurations

```ruby
# Use predefined platform configurations
overskill_service = AI::Prompts::AgentPromptService.for_platform(:overskill)
lovable_service = AI::Prompts::AgentPromptService.for_platform(:lovable)
generic_service = AI::Prompts::AgentPromptService.for_platform(:generic)

# With custom overrides
custom_service = AI::Prompts::AgentPromptService.for_platform(
  :overskill, 
  current_date: "2025-12-31"
)
```

## Available Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `current_date` | Current date (YYYY-MM-DD) | Date shown in prompt |
| `platform_name` | "OverSkill" | Name of the AI platform |
| `tool_prefix` | "os-" | Prefix for all tool names |
| `technology_stack` | "React, Vite, Tailwind CSS, and TypeScript" | Supported technologies |
| `backend_integration` | "Supabase" | Backend service name |
| `context_section_name` | "additional_data" | Name of context section |

## Advanced Usage

### Dynamic Variables with Lambdas

```ruby
service = AI::Prompts::AgentPromptService.new(
  current_date: -> { Date.current.strftime("%B %d, %Y") },
  platform_name: -> { Rails.application.class.module_parent_name }
)
```

### Validation

```ruby
service = AI::Prompts::AgentPromptService.new(platform_name: "")
if service.valid_config?
  config = service.generate_config
else
  Rails.logger.error "Invalid configuration: #{service.errors.full_messages}"
end
```

### Export for Debugging

```ruby
service = AI::Prompts::AgentPromptService.new
export_path = service.export_to_files
# Creates files at tmp/agent_config/prompt.txt, tools.json, metadata.json
```

## Integration Examples

### With AI Service Classes

```ruby
class AI::ChatService
  def initialize(platform: :overskill)
    @prompt_service = AI::Prompts::AgentPromptService.for_platform(platform)
  end

  def chat_with_agent(user_message)
    system_prompt = @prompt_service.generate_prompt
    tools_config = @prompt_service.generate_tools
    
    # Send to AI API with system prompt and tools
    ai_client.chat(
      messages: [
        { role: "system", content: system_prompt },
        { role: "user", content: user_message }
      ],
      tools: tools_config
    )
  end
end
```

### With Background Jobs

```ruby
class GenerateAppJob < ApplicationJob
  def perform(app_id, platform: :overskill)
    app = App.find(app_id)
    
    prompt_service = AI::Prompts::AgentPromptService.for_platform(
      platform,
      current_date: Date.current.strftime("%Y-%m-%d"),
      platform_name: app.team.platform_name || "OverSkill"
    )
    
    system_prompt = prompt_service.generate_prompt
    # Use prompt for app generation...
  end
end
```

### Environment-Specific Configurations

```ruby
# config/initializers/ai_prompts.rb
AI_PROMPT_CONFIG = case Rails.env
when 'development'
  { context_section_name: 'debug_context' }
when 'staging'
  { platform_name: 'OverSkill-Staging' }
when 'production'
  {} # Use defaults
else
  { platform_name: 'OverSkill-Test' }
end

# Usage
service = AI::Prompts::AgentPromptService.new(AI_PROMPT_CONFIG)
```

## File Structure

```
app/services/ai/prompts/
├── agent_prompt.rb           # Main prompt template handler
├── agent_tools.rb            # Tools configuration handler  
├── agent_prompt_service.rb   # Unified service interface
├── agent-prompt.txt          # Prompt template with {{variables}}
├── agent-tools.json          # Tools JSON with {{variables}}
└── README.md                 # This documentation
```

## Template Format

Templates use `{{variable_name}}` syntax for substitution:

```text
You are {{platform_name}}, an AI assistant.
Current date: {{current_date}}
Use tools with {{tool_prefix}} prefix.
```

## Error Handling

The system provides comprehensive error handling:

- **Missing templates**: Clear error messages with file paths
- **Invalid JSON**: JSON parsing errors with details
- **Missing variables**: Warnings for unsubstituted variables
- **Validation errors**: ActiveModel validations for required fields

## Testing

Run the test suite:

```bash
rails test test/services/ai/prompts/agent_prompt_service_test.rb
```

The tests cover:
- Variable substitution
- Platform configurations  
- JSON validity
- File export functionality
- Error handling
- Dynamic variable evaluation
