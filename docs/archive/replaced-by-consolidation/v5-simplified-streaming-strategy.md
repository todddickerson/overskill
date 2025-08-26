# V5 Simplified Streaming Strategy: Save & Refresh

## Core Concept
Instead of complex streaming logic, we simply:
1. **Update** the `AppChatMessage` model with new data
2. **Save** it to the database
3. **Broadcast** a single replace command to refresh the entire partial
4. Rails re-renders with the latest state

## Database Schema

```ruby
# Migration for AppChatMessage
class AddV5FieldsToAppChatMessages < ActiveRecord::Migration[7.0]
  def change
    add_column :app_chat_messages, :thinking_status, :string
    add_column :app_chat_messages, :thought_for_seconds, :integer
    add_column :app_chat_messages, :loop_messages, :jsonb, default: []
    add_column :app_chat_messages, :tool_calls, :jsonb, default: []
    add_column :app_chat_messages, :iteration_count, :integer, default: 0
    add_column :app_chat_messages, :is_code_generation, :boolean, default: false
    
    add_index :app_chat_messages, :loop_messages, using: :gin
    add_index :app_chat_messages, :tool_calls, using: :gin
  end
end
```

## Single Partial Approach

```erb
<!-- app/views/account/app_chat_messages/_agent_reply.html.erb -->
<div id="app_chat_message_<%= message.id %>" class="mb-4 agent-reply-container">
  
  <!-- OverSkill Logo -->
  <div class="flex items-start space-x-2">
    <%= image_tag "overskill-logo.svg", 
        alt: "OverSkill", 
        class: "w-6 h-6 flex-shrink-0" %>
    
    <div class="flex-1">
      <!-- 1. Thinking Status (only shows if present) -->
      <% if message.thinking_status.present? %>
        <div class="flex items-center space-x-2 text-sm text-gray-600 dark:text-gray-400 mb-2">
          <i class="fas fa-brain text-blue-500 animate-pulse"></i>
          <span><%= message.thinking_status %></span>
          <% if message.thought_for_seconds %>
            <span class="text-xs">(Thought for <%= message.thought_for_seconds %>s)</span>
          <% end %>
        </div>
      <% end %>
      
      <!-- 2. Loop Messages (main content) -->
      <% if message.loop_messages.any? %>
        <div class="space-y-2 mb-3">
          <% message.loop_messages.each do |msg| %>
            <div class="prose prose-sm dark:prose-invert max-w-none">
              <%= render_markdown(msg['content']) %>
            </div>
          <% end %>
        </div>
      <% end %>
      
      <!-- 3. Tool Calls (compressed by default) -->
      <% if message.tool_calls.any? %>
        <details class="mb-3 p-2 bg-gray-50 dark:bg-gray-800 rounded-lg">
          <summary class="cursor-pointer text-sm text-gray-600 dark:text-gray-400">
            <i class="fas fa-tools mr-1"></i>
            <%= message.tool_calls.count %> tools used
            <span class="text-xs text-blue-600 ml-2">Show All</span>
          </summary>
          
          <div class="mt-2 space-y-1">
            <% message.tool_calls.each do |tool| %>
              <div class="flex items-center space-x-2 text-xs text-gray-600">
                <i class="<%= tool_icon_for(tool['name']) %>"></i>
                <span class="font-medium"><%= tool['name'].gsub('os-', '') %></span>
                <% if tool['file_path'] %>
                  <span class="text-gray-500">[<%= tool['file_path'] %>]</span>
                <% end %>
              </div>
            <% end %>
          </div>
        </details>
      <% end %>
      
      <!-- 4. App Version Card (only if code was generated) -->
      <% if message.is_code_generation && message.app_version.present? %>
        <div class="mt-3 p-3 bg-gradient-to-r from-green-50 to-blue-50 
                    dark:from-green-900/20 dark:to-blue-900/20 
                    border border-green-200 dark:border-green-700 rounded-lg">
          
          <div class="flex items-center justify-between mb-2">
            <h4 class="font-medium text-gray-900 dark:text-gray-100">
              <%= message.app_version.formatted_display_name || "Version #{message.app_version.version_number}" %>
            </h4>
            <span class="text-xs px-2 py-1 bg-green-100 dark:bg-green-800 
                         text-green-800 dark:text-green-200 rounded-full">
              v<%= message.app_version.version_number %>
            </span>
          </div>
          
          <p class="text-sm text-gray-600 dark:text-gray-400 mb-3">
            <%= message.app_version.changelog || "AI Generated app based on your requirements" %>
          </p>
          
          <div class="flex items-center space-x-2">
            <%= link_to "Preview", 
                preview_account_app_version_path(message.app, message.app_version),
                class: "btn btn-sm btn-primary",
                target: "_blank",
                data: { turbo: false } %>
                
            <button class="btn btn-sm btn-secondary">
              <i class="fas fa-undo mr-1"></i>
              Restore
            </button>
            
            <button class="btn btn-sm btn-tertiary">
              <i class="fas fa-code mr-1"></i>
              View Code
            </button>
            
            <button class="btn btn-sm btn-tertiary">
              <i class="far fa-bookmark"></i>
              Bookmark
            </button>
          </div>
        </div>
      <% end %>
    </div>
  </div>
</div>
```

## Simplified Broadcasting in AppBuilderV5

```ruby
class AppBuilderV5
  def execute!
    @chat_message = create_assistant_message
    
    # Start the agent loop
    MAX_ITERATIONS.times do |iteration|
      @chat_message.iteration_count = iteration + 1
      
      # Step 1: Update thinking status
      update_and_broadcast("Analyzing your requirements...", thinking: true)
      
      # Step 2: Call Claude and get response
      response = call_claude_with_tools
      
      # Step 3: Add content to loop messages
      if response[:content].present?
        @chat_message.loop_messages << {
          content: response[:content],
          iteration: iteration + 1,
          timestamp: Time.current
        }
        update_and_broadcast
      end
      
      # Step 4: Process tool calls
      if response[:tool_calls].present?
        process_tools(response[:tool_calls])
      end
      
      # Step 5: Check if complete
      break if should_terminate?(response)
    end
    
    # Final update
    @chat_message.thinking_status = nil
    @chat_message.status = 'completed'
    update_and_broadcast
  end
  
  private
  
  def update_and_broadcast(thinking_status = nil, thinking: false)
    # Update thinking status if provided
    if thinking
      @chat_message.thinking_status = thinking_status
      @chat_message.thought_for_seconds = nil
    end
    
    # Save to database
    @chat_message.save!
    
    # Broadcast single replace command - Rails re-renders the entire partial
    @chat_message.broadcast_replace_to(
      "app_#{@app.id}_chat",
      target: "app_chat_message_#{@chat_message.id}",
      partial: "account/app_chat_messages/agent_reply",
      locals: { message: @chat_message }
    )
  end
  
  def process_tools(tool_calls)
    tool_calls.each do |tool_call|
      # Add to tool_calls array
      @chat_message.tool_calls << {
        name: tool_call['function']['name'],
        file_path: extract_file_path(tool_call),
        status: 'running',
        timestamp: Time.current
      }
      update_and_broadcast
      
      # Execute the tool
      result = execute_tool(tool_call)
      
      # Update status
      @chat_message.tool_calls.last['status'] = result[:success] ? 'complete' : 'error'
      update_and_broadcast
    end
  end
  
  def finalize_with_version
    if files_were_created?
      version = create_app_version
      @chat_message.app_version = version
      @chat_message.is_code_generation = true
      update_and_broadcast
    end
  end
end
```

## AppChatMessage Model Updates

```ruby
class AppChatMessage < ApplicationRecord
  # Existing code...
  
  # After any save, broadcast the update
  after_update_commit :broadcast_update
  
  private
  
  def broadcast_update
    broadcast_replace_to(
      "app_#{app.id}_chat",
      target: "app_chat_message_#{id}",
      partial: "account/app_chat_messages/agent_reply",
      locals: { message: self }
    )
  end
end
```

## Key Benefits of Simplified Approach

1. **Single Source of Truth**: The database is the source of truth
2. **No Complex State Management**: Just save and broadcast
3. **Automatic Consistency**: Partial always reflects current DB state
4. **Simple Debugging**: Can inspect DB to see exact state
5. **Rails Native**: Uses standard Rails patterns (no custom JS)
6. **Efficient**: One broadcast per update, Rails handles the rest

## Usage Flow

```ruby
# In AppBuilderV5, at each step:

# 1. Thinking
@chat_message.thinking_status = "Planning your app architecture..."
@chat_message.save!  # Triggers broadcast automatically

# 2. Add content
@chat_message.loop_messages << { content: "I'll create a todo app..." }
@chat_message.save!  # Triggers broadcast

# 3. Add tool
@chat_message.tool_calls << { name: "os-write", file_path: "src/App.tsx" }
@chat_message.save!  # Triggers broadcast

# 4. Complete with version
@chat_message.app_version = version
@chat_message.is_code_generation = true
@chat_message.save!  # Triggers broadcast
```

## Migration Path

1. Add JSONB columns to AppChatMessage
2. Create single `_agent_reply.html.erb` partial
3. Update AppChatMessage model with `after_update_commit`
4. Modify AppBuilderV5 to use save & broadcast pattern
5. Remove complex streaming logic from ChatProgressBroadcaster

This is MUCH simpler and more maintainable!