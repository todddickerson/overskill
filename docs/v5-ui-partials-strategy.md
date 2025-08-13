# V5 UI Partials Strategy: Agent Loop with Real-time Streaming

## Overview
The V5 UI implements a **single agent reply container** that dynamically updates its components via Turbo Streams as the agent loop progresses. This provides a cohesive, evolving message rather than multiple separate messages.

## Database Schema Enhancements

### AppChatMessage Model Updates
```ruby
# Add these fields to AppChatMessage
add_column :app_chat_messages, :thinking_status, :string
add_column :app_chat_messages, :thought_for_seconds, :integer
add_column :app_chat_messages, :loop_messages, :jsonb, default: []
add_column :app_chat_messages, :tool_calls, :jsonb, default: []
add_column :app_chat_messages, :iteration_count, :integer, default: 0
add_column :app_chat_messages, :is_code_generation, :boolean, default: false
```

## Partial Structure

### 1. Main Agent Reply Container
```erb
<!-- app/views/account/app_chat_messages/_agent_reply.html.erb -->
<div id="app_chat_message_<%= message.id %>" 
     class="mb-4 agent-reply-container"
     data-controller="agent-reply"
     data-agent-reply-message-id-value="<%= message.id %>">
  
  <!-- 1. Thinking Status (updates via Turbo Stream) -->
  <div id="thinking_status_<%= message.id %>">
    <%= render "account/app_chat_messages/agent_thinking_status", 
        message: message %>
  </div>
  
  <!-- 2. Loop Messages Container (appends new messages via stream) -->
  <div id="loop_messages_<%= message.id %>" 
       class="agent-loop-messages"
       data-agent-reply-target="loopMessages">
    <%= render "account/app_chat_messages/agent_loop_messages", 
        messages: message.loop_messages %>
  </div>
  
  <!-- 3. Tool Calls Section (updates via stream) -->
  <div id="tool_calls_<%= message.id %>">
    <%= render "account/app_chat_messages/agent_tool_calls", 
        tool_calls: message.tool_calls,
        message_id: message.id %>
  </div>
  
  <!-- 4. App Version Card (appears only if code generated) -->
  <% if message.is_code_generation && message.app_version.present? %>
    <div id="app_version_<%= message.id %>">
      <%= render "account/app_chat_messages/agent_app_version", 
          version: message.app_version %>
    </div>
  <% end %>
</div>
```

### 2. Thinking Status Component
```erb
<!-- app/views/account/app_chat_messages/_agent_thinking_status.html.erb -->
<% if message.thinking_status.present? %>
  <div class="flex items-start space-x-2 mb-3">
    <%= image_tag "overskill-logo.svg", 
        alt: "OverSkill", 
        class: "w-6 h-6 flex-shrink-0" %>
    
    <div class="flex items-center space-x-2 text-sm text-gray-600 dark:text-gray-400">
      <i class="fas fa-brain text-blue-500 animate-pulse"></i>
      <span class="thinking-text">
        <%= message.thinking_status %>
        <% if message.thought_for_seconds %>
          <span class="text-xs text-gray-500">
            (Thought for <%= message.thought_for_seconds %> seconds)
          </span>
        <% end %>
      </span>
    </div>
  </div>
<% end %>
```

### 3. Loop Messages Component
```erb
<!-- app/views/account/app_chat_messages/_agent_loop_messages.html.erb -->
<div class="space-y-3">
  <% messages.each_with_index do |loop_msg, index| %>
    <div class="agent-loop-message" 
         id="loop_message_<%= index %>"
         data-iteration="<%= loop_msg['iteration'] %>">
      
      <% if loop_msg['type'] == 'content' %>
        <!-- Regular markdown content -->
        <div class="prose prose-sm dark:prose-invert max-w-none">
          <%= render_markdown(loop_msg['content']) %>
        </div>
        
      <% elsif loop_msg['type'] == 'status' %>
        <!-- Status update (e.g., "Analyzing requirements...") -->
        <div class="flex items-center space-x-2 text-sm text-blue-600 dark:text-blue-400">
          <i class="fas fa-info-circle"></i>
          <span><%= loop_msg['content'] %></span>
        </div>
        
      <% elsif loop_msg['type'] == 'error' %>
        <!-- Error message -->
        <div class="flex items-center space-x-2 text-sm text-red-600 dark:text-red-400">
          <i class="fas fa-exclamation-triangle"></i>
          <span><%= loop_msg['content'] %></span>
        </div>
      <% end %>
    </div>
  <% end %>
</div>
```

### 4. Tool Calls Component (Compressed/Expanded)
```erb
<!-- app/views/account/app_chat_messages/_agent_tool_calls.html.erb -->
<% if tool_calls.any? %>
  <div class="agent-tool-calls mt-3 p-2 bg-gray-50 dark:bg-gray-800 rounded-lg"
       data-controller="expandable"
       data-expandable-expanded-value="false">
    
    <!-- Compressed View (Default) -->
    <div data-expandable-target="compressed" class="cursor-pointer"
         data-action="click->expandable#toggle">
      <div class="flex items-center justify-between text-sm">
        <div class="flex items-center space-x-2">
          <i class="fas fa-tools text-gray-500"></i>
          <span class="text-gray-700 dark:text-gray-300">
            <%= tool_calls.count %> tools used
          </span>
        </div>
        <button class="text-xs text-blue-600 hover:text-blue-700">
          Show All
        </button>
      </div>
    </div>
    
    <!-- Expanded View -->
    <div data-expandable-target="expanded" class="hidden mt-2 space-y-2">
      <% tool_calls.each do |tool| %>
        <div class="flex items-start space-x-2 text-xs">
          <% icon = tool_icon_for(tool['name']) %>
          <i class="<%= icon %> text-gray-400 mt-0.5"></i>
          
          <div class="flex-1">
            <span class="font-medium text-gray-700 dark:text-gray-300">
              <%= tool['name'].gsub('os-', '').humanize %>
            </span>
            
            <% if tool['file_path'] %>
              <span class="text-gray-500">
                [<%= tool['file_path'] %>]
              </span>
            <% end %>
            
            <% if tool['status'] == 'error' %>
              <span class="text-red-500 ml-2">
                <i class="fas fa-times-circle"></i> Failed
              </span>
            <% end %>
          </div>
          
          <button class="text-blue-600 hover:text-blue-700"
                  data-action="click->expandable#hide">
            Hide
          </button>
        </div>
      <% end %>
    </div>
  </div>
<% end %>
```

### 5. App Version Card Component
```erb
<!-- app/views/account/app_chat_messages/_agent_app_version.html.erb -->
<div class="mt-4 p-4 bg-gradient-to-r from-green-50 to-blue-50 
            dark:from-green-900/20 dark:to-blue-900/20 
            border border-green-200 dark:border-green-700 rounded-lg">
  
  <div class="flex items-center justify-between mb-3">
    <div>
      <h4 class="font-medium text-gray-900 dark:text-gray-100">
        <%= version.formatted_display_name || "App Version #{version.version_number}" %>
      </h4>
      <p class="text-sm text-gray-600 dark:text-gray-400">
        <%= version.changelog || "AI Generated - one sentence description" %>
      </p>
    </div>
    
    <span class="text-xs px-2 py-1 bg-green-100 dark:bg-green-800 
                 text-green-800 dark:text-green-200 rounded-full">
      v<%= version.version_number %>
    </span>
  </div>
  
  <div class="flex items-center space-x-3">
    <%= link_to preview_account_app_version_path(version.app, version),
        class: "btn btn-sm btn-primary",
        target: "_blank",
        title: "Click to Preview App Version",
        data: { turbo: false } do %>
      <i class="fas fa-external-link-alt mr-1"></i>
      Preview
    <% end %>
    
    <button class="btn btn-sm btn-secondary"
            title: "Restore this version">
      <i class="fas fa-undo mr-1"></i>
      Restore
    </button>
    
    <button class="btn btn-sm btn-tertiary"
            data-action="click->code-modal#open"
            data-version-id="<%= version.id %>"
            title: "View code changes">
      <i class="fas fa-code mr-1"></i>
      View Code
    </button>
    
    <button class="btn btn-sm btn-tertiary"
            data-action="click->bookmark#toggle"
            data-version-id="<%= version.id %>"
            title: "Bookmark for later">
      <i class="<%= version.bookmarked? ? 'fas' : 'far' %> fa-bookmark"></i>
    </button>
  </div>
</div>
```

## Streaming Implementation

### ChatProgressBroadcasterV2 Enhancements
```ruby
class ChatProgressBroadcasterV2
  def initialize(chat_message)
    @chat_message = chat_message
    @channel = "app_#{chat_message.app.id}_chat"
  end
  
  # Update thinking status
  def broadcast_thinking(status, seconds = nil)
    @chat_message.update!(
      thinking_status: status,
      thought_for_seconds: seconds
    )
    
    broadcast_replace_to @channel,
      target: "thinking_status_#{@chat_message.id}",
      partial: "account/app_chat_messages/agent_thinking_status",
      locals: { message: @chat_message }
  end
  
  # Append new loop message
  def broadcast_loop_message(content, type: 'content', iteration: nil)
    loop_msg = {
      content: content,
      type: type,
      iteration: iteration || @chat_message.iteration_count,
      timestamp: Time.current.iso8601
    }
    
    @chat_message.loop_messages << loop_msg
    @chat_message.save!
    
    broadcast_replace_to @channel,
      target: "loop_messages_#{@chat_message.id}",
      partial: "account/app_chat_messages/agent_loop_messages",
      locals: { messages: @chat_message.loop_messages }
  end
  
  # Update tool calls
  def broadcast_tool_execution(tool_name, file_path: nil, status: 'complete')
    tool_call = {
      name: tool_name,
      file_path: file_path,
      status: status,
      timestamp: Time.current.iso8601
    }
    
    @chat_message.tool_calls << tool_call
    @chat_message.save!
    
    broadcast_replace_to @channel,
      target: "tool_calls_#{@chat_message.id}",
      partial: "account/app_chat_messages/agent_tool_calls",
      locals: { 
        tool_calls: @chat_message.tool_calls,
        message_id: @chat_message.id
      }
  end
  
  # Final app version card
  def broadcast_app_version(app_version)
    @chat_message.update!(
      app_version: app_version,
      is_code_generation: true,
      status: 'completed'
    )
    
    broadcast_append_to @channel,
      target: "app_chat_message_#{@chat_message.id}",
      partial: "account/app_chat_messages/agent_app_version",
      locals: { version: app_version }
  end
end
```

## Usage in AppBuilderV5

```ruby
def execute_iteration
  # 1. Broadcast thinking
  broadcaster.broadcast_thinking("Analyzing your requirements...")
  
  # 2. Add loop message with analysis
  broadcaster.broadcast_loop_message(
    "I'll create a todo app with the following features...",
    type: 'content'
  )
  
  # 3. Execute tools with status updates
  tools.each do |tool|
    broadcaster.broadcast_tool_execution(
      tool[:name],
      file_path: tool[:file_path],
      status: 'running'
    )
    
    # Execute tool...
    
    broadcaster.broadcast_tool_execution(
      tool[:name],
      file_path: tool[:file_path],
      status: 'complete'
    )
  end
  
  # 4. If code generated, show app version
  if app_version_created?
    broadcaster.broadcast_app_version(app_version)
  end
end
```

## Key Benefits

1. **Single Container**: All updates happen within one message container
2. **Real-time Streaming**: Each component updates independently via Turbo Streams
3. **Progressive Disclosure**: Tool calls compressed by default, expandable for details
4. **Clean Separation**: Discussion-only messages don't show AppVersion card
5. **Iteration Tracking**: Shows progress through multiple agent loop iterations

## Stimulus Controllers

### agent-reply-controller.js
```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["loopMessages", "toolCalls"]
  
  connect() {
    // Auto-scroll to new content
    this.observeNewContent()
  }
  
  observeNewContent() {
    const observer = new MutationObserver(() => {
      this.scrollToBottom()
    })
    
    observer.observe(this.loopMessagesTarget, {
      childList: true,
      subtree: true
    })
  }
  
  scrollToBottom() {
    this.element.scrollIntoView({ 
      behavior: 'smooth', 
      block: 'end' 
    })
  }
}
```

## Migration Strategy

1. Add new JSONB columns to AppChatMessage
2. Create new partials in parallel with existing ones
3. Update ChatProgressBroadcasterV2 with new methods
4. Integrate with AppBuilderV5 agent loop
5. Test with real agent iterations
6. Deploy with feature flag for gradual rollout