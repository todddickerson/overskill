# WebSocket Tool Streaming Strategy - Option 4 Implementation Plan

## Executive Summary

OverSkill already has **80% of the infrastructure** needed for Netflix/Uber-grade real-time tool execution streaming. The foundation exists with ActionCable, Stimulus controllers, and Turbo Streams. This document outlines a comprehensive strategy to implement **Option 4: WebSocket Streaming Updates** for AppBuilderV5 tool execution.

## Current Infrastructure Analysis ✅

### Already Implemented:
1. **ActionCable WebSocket Infrastructure**
   - `ChatProgressChannel` - Real-time chat updates
   - `DeploymentChannel` - Deployment progress streaming
   - Authentication via `ApplicationCable::Connection`
   - User authorization and stream security

2. **Client-Side Real-Time Controllers**
   - `ChatProgressController` - Handles WebSocket messages, animations, and UI updates
   - Consumer management with automatic reconnection
   - Event-driven architecture with custom event handling

3. **Server-Side Broadcasting System**
   - `broadcast_message_update` - Already streams UI updates
   - Turbo Streams integration for DOM updates
   - Conversation flow tracking and incremental flushing

4. **Existing Tool Progress System**
   - `should_flush_incrementally?` - Smart batching strategy
   - `execute_and_format_tool_results` - Tool execution pipeline
   - Real-time conversation_flow updates

## Option 4: Enhanced WebSocket Streaming Architecture

### 🎯 Goal: Netflix-Grade Real-Time Tool Execution UX

Transform the current batched tool updates into **granular, real-time streaming** where users see:
- ✨ Individual tool execution as it happens
- 📊 Progress bars within each tool (file sizes, lines written, API calls)
- 🔄 Real-time status updates (starting → processing → validating → complete)
- 📈 Performance metrics (execution time, success rates)
- 🎬 Smooth animations and state transitions

## Technical Implementation Strategy

### Phase 1: Enhanced Streaming Foundation

#### 1.1 New ActionCable Channel: `ToolExecutionChannel`

```ruby
# app/channels/tool_execution_channel.rb
class ToolExecutionChannel < ApplicationCable::Channel
  def subscribed
    message = AppChatMessage.find(params[:message_id])
    
    if authorized_for_message?(message)
      stream_from "tool_execution_#{message.id}"
      stream_from "app_#{message.app.id}_tools"
      
      # Send initial tool queue state
      transmit({
        action: 'tool_queue_initialized',
        queue_size: message.pending_tool_count,
        estimated_duration: estimate_completion_time(message)
      })
    else
      reject
    end
  end
  
  def pause_tool_execution(data)
    # User can pause/resume tool execution
    ToolExecutionControlService.pause(params[:message_id])
  end
  
  def cancel_tool_execution(data)
    # User can cancel long-running tools
    ToolExecutionControlService.cancel(params[:message_id])
  end
  
  def request_tool_details(data)
    # User can get detailed progress for specific tool
    transmit(get_tool_execution_details(data['tool_index']))
  end
end
```

#### 1.2 Enhanced AppBuilderV5 Integration

```ruby
# Enhanced execute_and_format_tool_results with real-time streaming
def execute_and_format_tool_results_websocket(tool_calls)
  tool_results = []
  
  # Broadcast initial tool execution plan
  broadcast_tool_execution_started(tool_calls)
  
  tool_calls.each_with_index do |tool_call, index|
    # Broadcast "starting tool X of Y"
    broadcast_tool_status(index, 'starting', {
      tool_name: tool_call['function']['name'],
      description: get_tool_description(tool_call),
      estimated_duration: estimate_tool_duration(tool_call)
    })
    
    # Execute tool with real-time progress callbacks
    result = execute_single_tool_with_streaming_progress(tool_call, index) do |progress_data|
      # Real-time progress within tool execution
      broadcast_tool_progress(index, progress_data)
    end
    
    # Broadcast completion with metrics
    broadcast_tool_status(index, 'complete', {
      result: result,
      execution_time: result[:execution_time],
      success: result[:success],
      metrics: result[:metrics]
    })
    
    tool_results << result
  end
  
  # Broadcast final summary
  broadcast_tool_execution_complete({
    total_tools: tool_calls.size,
    successful: tool_results.count { |r| r[:success] },
    total_execution_time: tool_results.sum { |r| r[:execution_time] || 0 },
    files_created: tool_results.sum { |r| r[:files_created] || 0 },
    lines_written: tool_results.sum { |r| r[:lines_written] || 0 }
  })
  
  tool_results
end
```

### Phase 2: Granular Tool Progress Streaming

#### 2.1 Enhanced Tool Execution Service

```ruby
# app/services/ai/streaming_tool_executor.rb
class StreamingToolExecutor
  def initialize(message_id)
    @message_id = message_id
    @channel = "tool_execution_#{message_id}"
  end
  
  def execute_with_streaming(tool_call, tool_index)
    tool_name = tool_call['function']['name']
    start_time = Time.current
    
    case tool_name
    when 'os-write'
      execute_write_with_streaming(tool_call, tool_index)
    when 'os-line-replace' 
      execute_line_replace_with_streaming(tool_call, tool_index)
    when 'generate_image'
      execute_image_generation_with_streaming(tool_call, tool_index)
    when 'web_search'
      execute_web_search_with_streaming(tool_call, tool_index)
    else
      execute_generic_tool_with_streaming(tool_call, tool_index)
    end
  ensure
    execution_time = Time.current - start_time
    broadcast_tool_metrics(tool_index, {
      execution_time: execution_time,
      memory_used: get_memory_usage,
      api_calls_made: @api_calls_count || 0
    })
  end
  
  private
  
  def execute_write_with_streaming(tool_call, index)
    file_path = tool_call['function']['arguments']['file_path'] 
    content = tool_call['function']['arguments']['content']
    
    # Progress: File analysis
    broadcast_progress(index, {
      stage: 'analyzing',
      message: "Analyzing file structure...",
      progress: 10
    })
    
    file_info = analyze_file_content(content)
    
    # Progress: Content validation
    broadcast_progress(index, {
      stage: 'validating', 
      message: "Validating content and dependencies...",
      progress: 30,
      details: {
        file_size: content.bytesize,
        line_count: content.lines.count,
        imports_detected: file_info[:imports].count
      }
    })
    
    # Progress: Writing file
    broadcast_progress(index, {
      stage: 'writing',
      message: "Writing #{file_path}...", 
      progress: 60,
      details: {
        bytes_written: 0,
        total_bytes: content.bytesize
      }
    })
    
    # Simulate chunked writing for large files
    result = write_file_with_progress(file_path, content) do |bytes_written|
      progress_pct = 60 + (bytes_written.to_f / content.bytesize * 30)
      broadcast_progress(index, {
        stage: 'writing',
        progress: progress_pct.to_i,
        details: { bytes_written: bytes_written, total_bytes: content.bytesize }
      })
    end
    
    # Progress: Validation complete
    broadcast_progress(index, {
      stage: 'complete',
      message: "File #{file_path} created successfully",
      progress: 100,
      details: {
        file_size: result[:file_size],
        lines_written: result[:lines_written],
        components_detected: file_info[:components]
      }
    })
    
    result
  end
  
  def execute_image_generation_with_streaming(tool_call, index)
    prompt = tool_call['function']['arguments']['prompt']
    
    # Progress: Preparing generation
    broadcast_progress(index, {
      stage: 'preparing',
      message: "Preparing image generation...",
      progress: 5
    })
    
    # Progress: Calling AI service
    broadcast_progress(index, {
      stage: 'generating',
      message: "Generating image with AI...",
      progress: 15,
      details: { prompt: prompt.truncate(100) }
    })
    
    # Progress: AI processing (simulated progress)
    simulate_ai_generation_progress(index, 15, 70)
    
    result = generate_image_actual(tool_call)
    
    if result[:success]
      # Progress: Uploading to R2
      broadcast_progress(index, {
        stage: 'uploading',
        message: "Uploading to R2 bucket...",
        progress: 80
      })
      
      upload_result = upload_to_r2_with_progress(result[:image_data]) do |uploaded_bytes, total_bytes|
        progress_pct = 80 + (uploaded_bytes.to_f / total_bytes * 15)
        broadcast_progress(index, {
          stage: 'uploading',
          progress: progress_pct.to_i,
          details: { uploaded_bytes: uploaded_bytes, total_bytes: total_bytes }
        })
      end
      
      # Progress: Complete
      broadcast_progress(index, {
        stage: 'complete',
        message: "Image generated and uploaded successfully",
        progress: 100,
        details: {
          image_url: upload_result[:url],
          image_size: upload_result[:file_size],
          dimensions: "#{result[:width]}x#{result[:height]}"
        }
      })
    end
    
    result
  end
  
  def broadcast_progress(tool_index, progress_data)
    ActionCable.server.broadcast(@channel, {
      action: 'tool_progress_update',
      tool_index: tool_index,
      timestamp: Time.current.iso8601,
      **progress_data
    })
  end
end
```

#### 2.2 Client-Side: Enhanced Tool Progress Controller

```javascript
// app/javascript/controllers/tool_execution_controller.js
import { Controller } from "@hotwired/stimulus"
import consumer from "../channels/consumer"

export default class extends Controller {
  static targets = ["toolList", "overallProgress", "toolTemplate"]
  static values = { messageId: Number }
  
  connect() {
    this.toolExecutions = new Map()
    this.overallStats = { completed: 0, total: 0, startTime: Date.now() }
    
    this.subscription = consumer.subscriptions.create(
      {
        channel: "ToolExecutionChannel",
        message_id: this.messageIdValue
      },
      {
        received: (data) => this.handleToolStreamingData(data),
        connected: () => this.onWebSocketConnected(),
        disconnected: () => this.onWebSocketDisconnected()
      }
    )
  }
  
  handleToolStreamingData(data) {
    switch(data.action) {
      case 'tool_execution_started':
        this.initializeToolList(data.tools)
        break
      case 'tool_status_update': 
        this.updateToolStatus(data.tool_index, data)
        break
      case 'tool_progress_update':
        this.updateToolProgress(data.tool_index, data)
        break
      case 'tool_execution_complete':
        this.showExecutionSummary(data)
        break
    }
  }
  
  initializeToolList(tools) {
    this.overallStats.total = tools.length
    
    tools.forEach((tool, index) => {
      const toolElement = this.createToolElement(tool, index)
      this.toolListTarget.appendChild(toolElement)
    })
    
    this.updateOverallProgress()
  }
  
  createToolElement(tool, index) {
    const template = this.toolTemplateTarget.content.cloneNode(true)
    const toolDiv = template.querySelector('.tool-execution-item')
    
    toolDiv.id = `tool-${index}`
    toolDiv.querySelector('.tool-name').textContent = tool.name
    toolDiv.querySelector('.tool-description').textContent = tool.description
    toolDiv.querySelector('.estimated-duration').textContent = `~${tool.estimated_duration}s`
    
    return template
  }
  
  updateToolStatus(toolIndex, data) {
    const toolElement = this.element.querySelector(`#tool-${toolIndex}`)
    if (!toolElement) return
    
    const statusBadge = toolElement.querySelector('.status-badge')
    const statusText = toolElement.querySelector('.status-text')
    
    switch(data.status) {
      case 'starting':
        statusBadge.className = 'status-badge bg-yellow-500 animate-pulse'
        statusText.textContent = 'Starting...'
        this.animateToolStart(toolElement)
        break
      case 'complete':
        statusBadge.className = 'status-badge bg-green-500'
        statusText.textContent = `Complete (${data.execution_time}s)`
        this.animateToolComplete(toolElement)
        this.overallStats.completed++
        this.updateOverallProgress()
        break
    }
  }
  
  updateToolProgress(toolIndex, data) {
    const toolElement = this.element.querySelector(`#tool-${toolIndex}`)
    if (!toolElement) return
    
    const progressBar = toolElement.querySelector('.progress-bar')
    const progressText = toolElement.querySelector('.progress-text')
    const detailsText = toolElement.querySelector('.progress-details')
    
    // Animate progress bar
    progressBar.style.width = `${data.progress}%`
    progressText.textContent = `${data.progress}% - ${data.message}`
    
    // Show detailed progress info
    if (data.details) {
      let detailsHtml = ''
      Object.entries(data.details).forEach(([key, value]) => {
        detailsHtml += `<span class="detail-item">${key}: ${value}</span>`
      })
      detailsText.innerHTML = detailsHtml
    }
    
    // Add stage-specific styling
    this.updateProgressBarColor(progressBar, data.stage)
  }
  
  updateProgressBarColor(progressBar, stage) {
    progressBar.className = 'progress-bar transition-all duration-300'
    
    switch(stage) {
      case 'analyzing':
        progressBar.classList.add('bg-blue-500')
        break
      case 'generating':
        progressBar.classList.add('bg-purple-500', 'animate-pulse')
        break
      case 'uploading':
        progressBar.classList.add('bg-orange-500')
        break
      case 'complete':
        progressBar.classList.add('bg-green-500')
        break
      default:
        progressBar.classList.add('bg-gray-500')
    }
  }
  
  updateOverallProgress() {
    const progressPct = (this.overallStats.completed / this.overallStats.total) * 100
    const elapsed = (Date.now() - this.overallStats.startTime) / 1000
    const estimated = elapsed / this.overallStats.completed * this.overallStats.total
    
    this.overallProgressTarget.innerHTML = `
      <div class="overall-stats">
        <div class="progress-summary">
          ${this.overallStats.completed}/${this.overallStats.total} tools completed (${Math.round(progressPct)}%)
        </div>
        <div class="time-stats">
          Elapsed: ${Math.round(elapsed)}s | ETA: ${Math.round(estimated - elapsed)}s
        </div>
        <div class="progress-bar-container">
          <div class="progress-bar bg-gradient-to-r from-blue-500 to-green-500" 
               style="width: ${progressPct}%"></div>
        </div>
      </div>
    `
  }
  
  animateToolStart(toolElement) {
    toolElement.classList.add('scale-105', 'ring-2', 'ring-yellow-500', 'ring-opacity-50')
    setTimeout(() => {
      toolElement.classList.remove('scale-105')
    }, 300)
  }
  
  animateToolComplete(toolElement) {
    toolElement.classList.add('bg-green-50', 'ring-2', 'ring-green-500', 'ring-opacity-30')
    
    // Add checkmark animation
    const checkmark = toolElement.querySelector('.checkmark')
    if (checkmark) {
      checkmark.classList.add('animate-checkmark')
    }
  }
  
  showExecutionSummary(data) {
    // Create beautiful summary modal/panel
    const summaryHtml = `
      <div class="execution-summary animate-fade-in">
        <h3>🎉 Tool Execution Complete!</h3>
        <div class="summary-stats">
          <div class="stat">
            <span class="stat-number">${data.successful}/${data.total_tools}</span>
            <span class="stat-label">Tools Successful</span>
          </div>
          <div class="stat">
            <span class="stat-number">${Math.round(data.total_execution_time)}s</span>
            <span class="stat-label">Total Time</span>
          </div>
          <div class="stat">
            <span class="stat-number">${data.files_created}</span>
            <span class="stat-label">Files Created</span>
          </div>
          <div class="stat">
            <span class="stat-number">${data.lines_written}</span>
            <span class="stat-label">Lines Written</span>
          </div>
        </div>
      </div>
    `
    
    this.element.insertAdjacentHTML('beforeend', summaryHtml)
    
    // Trigger celebration animation
    this.triggerCelebrationEffect()
  }
  
  triggerCelebrationEffect() {
    // Netflix-style success animation
    this.element.classList.add('animate-success-glow')
    
    setTimeout(() => {
      this.element.classList.remove('animate-success-glow')
    }, 2000)
  }
}
```

### Phase 3: Advanced UX Features

#### 3.1 Real-Time Performance Dashboard

```erb
<!-- Enhanced Tool Execution UI Template -->
<template data-tool-execution-target="toolTemplate">
  <div class="tool-execution-item border rounded-lg p-4 mb-3 transition-all duration-300">
    <div class="flex items-center justify-between mb-2">
      <div class="flex items-center space-x-3">
        <div class="status-badge w-3 h-3 rounded-full bg-gray-400"></div>
        <h4 class="tool-name font-medium text-gray-900"></h4>
        <span class="tool-description text-sm text-gray-600"></span>
      </div>
      <div class="flex items-center space-x-2 text-sm text-gray-500">
        <span class="estimated-duration"></span>
        <div class="checkmark hidden">
          <svg class="w-4 h-4 text-green-500" fill="currentColor" viewBox="0 0 20 20">
            <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z"/>
          </svg>
        </div>
      </div>
    </div>
    
    <div class="progress-container mb-2">
      <div class="progress-bar-container bg-gray-200 rounded-full h-2 overflow-hidden">
        <div class="progress-bar h-full transition-all duration-300" style="width: 0%"></div>
      </div>
      <div class="progress-text text-sm text-gray-600 mt-1"></div>
    </div>
    
    <div class="progress-details text-xs text-gray-500 space-x-4"></div>
  </div>
</template>
```

#### 3.2 User Control Features

```ruby
# app/services/ai/tool_execution_control_service.rb
class ToolExecutionControlService
  def self.pause(message_id)
    # Implement pause/resume functionality
    Rails.cache.write("tool_execution_paused_#{message_id}", true, expires_in: 1.hour)
    
    ActionCable.server.broadcast("tool_execution_#{message_id}", {
      action: 'execution_paused',
      message: 'Tool execution paused by user'
    })
  end
  
  def self.resume(message_id)
    Rails.cache.delete("tool_execution_paused_#{message_id}")
    
    ActionCable.server.broadcast("tool_execution_#{message_id}", {
      action: 'execution_resumed', 
      message: 'Tool execution resumed'
    })
  end
  
  def self.cancel(message_id)
    Rails.cache.write("tool_execution_cancelled_#{message_id}", true, expires_in: 1.hour)
    
    ActionCable.server.broadcast("tool_execution_#{message_id}", {
      action: 'execution_cancelled',
      message: 'Tool execution cancelled by user'
    })
  end
end
```

## Parallel Background Tool Execution Strategy

### Background Job Architecture for Tool Calls

#### Core Concept: Async Tool Execution Pipeline
Instead of executing tools synchronously within the LLM conversation flow, tools are dispatched to background jobs for parallel execution. The LLM conversation pauses while waiting for results, with automatic timeout handling for stuck operations.

#### 4.1 Tool Execution Job Architecture

```ruby
# app/jobs/tool_execution_job.rb
class ToolExecutionJob < ApplicationJob
  queue_as :tool_execution
  sidekiq_options retry: 2, dead: false
  
  def perform(app_chat_message_id, tool_call_batch_id, tool_call, tool_index)
    message = AppChatMessage.find(app_chat_message_id)
    batch = ToolCallBatch.find(tool_call_batch_id)
    
    # Update status to executing
    batch.tool_executions.find_by(tool_index: tool_index).update!(
      status: 'executing',
      started_at: Time.current
    )
    
    # Execute with timeout wrapper
    result = Timeout.timeout(tool_timeout_seconds(tool_call)) do
      execute_tool_with_streaming(message, tool_call, tool_index)
    end
    
    # Store result and mark complete
    batch.tool_executions.find_by(tool_index: tool_index).update!(
      status: 'completed',
      completed_at: Time.current,
      result: result.to_json,
      success: result[:success]
    )
    
    # Check if all tools in batch are complete
    if batch.all_tools_complete?
      ResumeLLMConversationJob.perform_later(app_chat_message_id, tool_call_batch_id)
    end
    
  rescue Timeout::Error => e
    handle_timeout(batch, tool_index, e)
  rescue => e
    handle_error(batch, tool_index, e)
  end
  
  private
  
  def tool_timeout_seconds(tool_call)
    case tool_call['function']['name']
    when 'generate_image'
      240 # 4 minutes for image generation
    when 'web_search'
      30  # 30 seconds for web search
    when 'os-write', 'os-line-replace'
      10  # 10 seconds for file operations
    else
      60  # Default 1 minute timeout
    end
  end
  
  def handle_timeout(batch, tool_index, error)
    batch.tool_executions.find_by(tool_index: tool_index).update!(
      status: 'timeout',
      completed_at: Time.current,
      error: "Tool execution timed out after #{tool_timeout_seconds} seconds",
      success: false
    )
    
    # Broadcast timeout to websocket
    ActionCable.server.broadcast("tool_execution_#{batch.app_chat_message_id}", {
      action: 'tool_timeout',
      tool_index: tool_index,
      error: error.message
    })
  end
end
```

#### 4.2 Tool Call Batch Management

```ruby
# app/models/tool_call_batch.rb
class ToolCallBatch < ApplicationRecord
  belongs_to :app_chat_message
  has_many :tool_executions, dependent: :destroy
  
  enum status: {
    pending: 'pending',
    executing: 'executing',
    completed: 'completed',
    timeout: 'timeout',
    failed: 'failed'
  }
  
  MAX_WAIT_TIME = 5.minutes
  
  def all_tools_complete?
    tool_executions.all? { |te| te.completed? || te.timeout? || te.failed? }
  end
  
  def successful_tools
    tool_executions.where(success: true)
  end
  
  def timeout_if_stuck!
    return unless executing?
    return unless created_at < MAX_WAIT_TIME.ago
    
    # Mark any still-executing tools as timeout
    tool_executions.executing.update_all(
      status: 'timeout',
      completed_at: Time.current,
      error: "Tool execution exceeded maximum wait time of #{MAX_WAIT_TIME.inspect}"
    )
    
    update!(status: 'timeout')
    
    # Resume LLM conversation with partial results
    ResumeLLMConversationJob.perform_later(app_chat_message_id, id)
  end
end

# app/models/tool_execution.rb
class ToolExecution < ApplicationRecord
  belongs_to :tool_call_batch
  
  enum status: {
    pending: 'pending',
    executing: 'executing',
    completed: 'completed',
    timeout: 'timeout',
    failed: 'failed'
  }
  
  def execution_time
    return nil unless started_at && completed_at
    completed_at - started_at
  end
end
```

#### 4.3 LLM Conversation Pause/Resume Mechanism

```ruby
# app/services/ai/tool_execution_dispatcher.rb
class ToolExecutionDispatcher
  def initialize(app_chat_message)
    @message = app_chat_message
  end
  
  def dispatch_tool_calls(tool_calls)
    return [] if tool_calls.empty?
    
    # Create batch for tracking
    batch = ToolCallBatch.create!(
      app_chat_message: @message,
      status: 'pending',
      total_tools: tool_calls.size
    )
    
    # Create execution records
    tool_calls.each_with_index do |tool_call, index|
      batch.tool_executions.create!(
        tool_index: index,
        tool_name: tool_call['function']['name'],
        tool_args: tool_call['function']['arguments'],
        status: 'pending'
      )
    end
    
    # Dispatch to background jobs for parallel execution
    tool_calls.each_with_index do |tool_call, index|
      ToolExecutionJob.perform_later(@message.id, batch.id, tool_call, index)
    end
    
    # Update batch status
    batch.update!(status: 'executing')
    
    # Broadcast execution started
    broadcast_batch_started(batch)
    
    # Schedule timeout check
    ToolExecutionTimeoutJob.set(wait: ToolCallBatch::MAX_WAIT_TIME)
      .perform_later(batch.id)
    
    batch
  end
  
  private
  
  def broadcast_batch_started(batch)
    ActionCable.server.broadcast("tool_execution_#{@message.id}", {
      action: 'batch_execution_started',
      batch_id: batch.id,
      total_tools: batch.total_tools,
      estimated_completion: estimate_completion_time(batch)
    })
  end
end
```

#### 4.4 Resume LLM Conversation Job

```ruby
# app/jobs/resume_llm_conversation_job.rb
class ResumeLLMConversationJob < ApplicationJob
  queue_as :critical
  
  def perform(app_chat_message_id, tool_call_batch_id)
    message = AppChatMessage.find(app_chat_message_id)
    batch = ToolCallBatch.find(tool_call_batch_id)
    
    # Collect results from completed tools
    tool_results = collect_tool_results(batch)
    
    # Update message with tool results
    message.update!(
      tool_results: tool_results,
      status: 'resuming_conversation'
    )
    
    # Resume LLM conversation with results
    AppBuilderV5.new(message).resume_with_tool_results(tool_results, batch)
    
  rescue => e
    Rails.logger.error "Failed to resume LLM conversation: #{e.message}"
    message.update!(status: 'error', error: e.message)
  end
  
  private
  
  def collect_tool_results(batch)
    batch.tool_executions.map do |execution|
      if execution.completed? && execution.success?
        {
          tool_index: execution.tool_index,
          tool_name: execution.tool_name,
          result: JSON.parse(execution.result),
          execution_time: execution.execution_time
        }
      else
        {
          tool_index: execution.tool_index,
          tool_name: execution.tool_name,
          error: execution.error || "Tool execution #{execution.status}",
          status: execution.status
        }
      end
    end
  end
end
```

#### 4.5 Timeout Monitoring Job

```ruby
# app/jobs/tool_execution_timeout_job.rb
class ToolExecutionTimeoutJob < ApplicationJob
  queue_as :default
  
  def perform(tool_call_batch_id)
    batch = ToolCallBatch.find(tool_call_batch_id)
    
    # Check if batch is still executing
    return unless batch.executing?
    
    # Check for stuck executions
    batch.timeout_if_stuck!
    
    # Broadcast timeout status
    if batch.timeout?
      ActionCable.server.broadcast("tool_execution_#{batch.app_chat_message_id}", {
        action: 'batch_timeout',
        batch_id: batch.id,
        message: 'Some tools exceeded maximum execution time'
      })
    end
  end
end
```

#### 4.6 Enhanced AppBuilderV5 Integration

```ruby
# Modification to app/services/ai/app_builder_v5.rb
class AppBuilderV5
  def execute_and_format_tool_results(tool_calls)
    # Check if parallel execution is enabled
    if Rails.configuration.parallel_tool_execution
      execute_tools_in_parallel(tool_calls)
    else
      execute_tools_synchronously(tool_calls)
    end
  end
  
  private
  
  def execute_tools_in_parallel(tool_calls)
    # Dispatch tools to background jobs
    dispatcher = ToolExecutionDispatcher.new(@app_chat_message)
    batch = dispatcher.dispatch_tool_calls(tool_calls)
    
    # Update conversation state to paused
    @app_chat_message.update!(
      conversation_state: 'paused_for_tools',
      tool_batch_id: batch.id
    )
    
    # Return placeholder indicating async execution
    {
      status: 'executing_async',
      batch_id: batch.id,
      message: "Executing #{tool_calls.size} tools in parallel..."
    }
  end
  
  def resume_with_tool_results(tool_results, batch)
    # Update conversation with tool results
    @conversation_flow.assistant('tool_results', {
      results: tool_results,
      batch_summary: generate_batch_summary(batch)
    })
    
    # Continue LLM conversation with results
    continue_conversation_with_results(tool_results)
  end
  
  def continue_conversation_with_results(tool_results)
    # Format results for LLM
    formatted_results = format_tool_results_for_llm(tool_results)
    
    # Add to conversation
    messages = @messages + [{
      role: "tool",
      content: formatted_results
    }]
    
    # Continue with next LLM call
    response = make_api_call_with_retry(messages)
    process_llm_response(response)
  end
  
  def format_tool_results_for_llm(tool_results)
    tool_results.map do |result|
      if result[:error]
        "Tool '#{result[:tool_name]}' failed: #{result[:error]}"
      else
        "Tool '#{result[:tool_name]}' completed successfully:\n#{result[:result].to_json}"
      end
    end.join("\n\n")
  end
end
```

### Configuration and Feature Flags

```ruby
# config/application.rb
config.parallel_tool_execution = ENV.fetch('PARALLEL_TOOL_EXECUTION', 'true') == 'true'
config.tool_execution_max_wait = ENV.fetch('TOOL_EXECUTION_MAX_WAIT', '5').to_i.minutes
config.tool_execution_default_timeout = ENV.fetch('TOOL_EXECUTION_DEFAULT_TIMEOUT', '60').to_i.seconds

# config/sidekiq.yml
:queues:
  - [critical, 10]        # Resume LLM conversation jobs
  - [tool_execution, 8]    # Parallel tool execution jobs
  - [tool_timeout, 5]      # Timeout monitoring jobs
  - [default, 3]
  - [low, 1]

:concurrency: 25
:max_retries: 2
```

### Failure Recovery and Retry Strategy

```ruby
# app/services/ai/tool_failure_recovery_service.rb
class ToolFailureRecoveryService
  MAX_RETRIES = 2
  
  def initialize(tool_execution, error)
    @execution = tool_execution
    @error = error
    @batch = @execution.tool_call_batch
  end
  
  def handle_failure
    if should_retry?
      retry_execution
    else
      mark_as_failed
      check_batch_completion
    end
  end
  
  private
  
  def should_retry?
    @execution.retry_count < MAX_RETRIES && retryable_error?
  end
  
  def retryable_error?
    case @error
    when Net::ReadTimeout, Timeout::Error
      true
    when StandardError
      @error.message.include?('temporary') || @error.message.include?('rate limit')
    else
      false
    end
  end
  
  def retry_execution
    @execution.increment!(:retry_count)
    
    # Re-queue with exponential backoff
    wait_time = (2 ** @execution.retry_count).seconds
    ToolExecutionJob.set(wait: wait_time).perform_later(
      @batch.app_chat_message_id,
      @batch.id,
      @execution.tool_args,
      @execution.tool_index
    )
    
    # Broadcast retry status
    broadcast_retry_status
  end
  
  def mark_as_failed
    @execution.update!(
      status: 'failed',
      completed_at: Time.current,
      error: @error.message,
      success: false
    )
    
    # Broadcast failure
    broadcast_failure_status
  end
  
  def check_batch_completion
    if @batch.all_tools_complete?
      # Resume conversation even with failures
      ResumeLLMConversationJob.perform_later(
        @batch.app_chat_message_id,
        @batch.id
      )
    end
  end
  
  def broadcast_retry_status
    ActionCable.server.broadcast("tool_execution_#{@batch.app_chat_message_id}", {
      action: 'tool_retry',
      tool_index: @execution.tool_index,
      retry_count: @execution.retry_count,
      message: "Retrying #{@execution.tool_name} (attempt #{@execution.retry_count + 1})"
    })
  end
  
  def broadcast_failure_status
    ActionCable.server.broadcast("tool_execution_#{@batch.app_chat_message_id}", {
      action: 'tool_failed',
      tool_index: @execution.tool_index,
      error: @error.message,
      tool_name: @execution.tool_name
    })
  end
end
```

### Real-time Status Broadcasting During Parallel Execution

```ruby
# app/services/ai/parallel_execution_broadcaster.rb
class ParallelExecutionBroadcaster
  def self.broadcast_batch_progress(batch)
    completed = batch.tool_executions.completed.count
    failed = batch.tool_executions.failed.count
    executing = batch.tool_executions.executing.count
    pending = batch.tool_executions.pending.count
    
    ActionCable.server.broadcast("tool_execution_#{batch.app_chat_message_id}", {
      action: 'batch_progress',
      batch_id: batch.id,
      stats: {
        completed: completed,
        failed: failed,
        executing: executing,
        pending: pending,
        total: batch.total_tools,
        progress_percentage: (completed + failed).to_f / batch.total_tools * 100
      },
      estimated_completion: estimate_completion(batch),
      elapsed_time: Time.current - batch.created_at
    })
  end
  
  def self.broadcast_tool_start(batch, tool_execution)
    ActionCable.server.broadcast("tool_execution_#{batch.app_chat_message_id}", {
      action: 'tool_started',
      tool_index: tool_execution.tool_index,
      tool_name: tool_execution.tool_name,
      timestamp: Time.current.iso8601,
      parallel_count: batch.tool_executions.executing.count
    })
  end
  
  def self.broadcast_tool_complete(batch, tool_execution, result)
    ActionCable.server.broadcast("tool_execution_#{batch.app_chat_message_id}", {
      action: 'tool_completed',
      tool_index: tool_execution.tool_index,
      tool_name: tool_execution.tool_name,
      success: tool_execution.success?,
      execution_time: tool_execution.execution_time,
      result_summary: summarize_result(result),
      timestamp: Time.current.iso8601
    })
    
    # Also broadcast overall batch progress
    broadcast_batch_progress(batch)
  end
  
  private
  
  def self.estimate_completion(batch)
    completed_rate = batch.tool_executions.completed.average(:execution_time) || 10
    remaining = batch.tool_executions.pending.count + batch.tool_executions.executing.count
    
    (remaining * completed_rate).seconds.from_now
  end
  
  def self.summarize_result(result)
    case result
    when Hash
      if result[:files_created]
        "Created #{result[:files_created]} files"
      elsif result[:lines_changed]
        "Modified #{result[:lines_changed]} lines"
      elsif result[:image_url]
        "Generated image successfully"
      else
        "Operation completed"
      end
    else
      "Completed successfully"
    end
  end
end
```

### Database Schema Updates

```ruby
# db/migrate/add_tool_execution_tracking.rb
class AddToolExecutionTracking < ActiveRecord::Migration[7.0]
  def change
    create_table :tool_call_batches do |t|
      t.references :app_chat_message, null: false, foreign_key: true
      t.string :status, default: 'pending'
      t.integer :total_tools
      t.datetime :started_at
      t.datetime :completed_at
      t.integer :successful_count, default: 0
      t.integer :failed_count, default: 0
      t.float :total_execution_time
      t.timestamps
    end
    
    create_table :tool_executions do |t|
      t.references :tool_call_batch, null: false, foreign_key: true
      t.integer :tool_index
      t.string :tool_name
      t.json :tool_args
      t.string :status, default: 'pending'
      t.datetime :started_at
      t.datetime :completed_at
      t.json :result
      t.text :error
      t.boolean :success, default: false
      t.integer :retry_count, default: 0
      t.float :execution_time
      t.timestamps
    end
    
    add_index :tool_call_batches, :status
    add_index :tool_call_batches, :created_at
    add_index :tool_executions, [:tool_call_batch_id, :tool_index]
    add_index :tool_executions, :status
    add_index :tool_executions, [:tool_call_batch_id, :status]
    
    add_column :app_chat_messages, :conversation_state, :string
    add_column :app_chat_messages, :tool_batch_id, :integer
    add_index :app_chat_messages, :conversation_state
  end
end
```

### Integration with Existing Conversation Flow

```ruby
# app/services/ai/conversation_state_manager.rb
class ConversationStateManager
  STATES = {
    active: 'active',
    paused_for_tools: 'paused_for_tools',
    resuming: 'resuming',
    completed: 'completed',
    error: 'error'
  }.freeze
  
  def initialize(app_chat_message)
    @message = app_chat_message
  end
  
  def pause_for_tools(batch)
    @message.update!(
      conversation_state: STATES[:paused_for_tools],
      tool_batch_id: batch.id
    )
    
    # Broadcast pause state
    broadcast_state_change(STATES[:paused_for_tools], {
      batch_id: batch.id,
      total_tools: batch.total_tools,
      message: "Executing #{batch.total_tools} tools in parallel..."
    })
  end
  
  def resume_conversation
    @message.update!(conversation_state: STATES[:resuming])
    
    broadcast_state_change(STATES[:resuming], {
      message: "Processing tool results and continuing conversation..."
    })
  end
  
  def mark_completed
    @message.update!(conversation_state: STATES[:completed])
    
    broadcast_state_change(STATES[:completed], {
      message: "Conversation completed successfully"
    })
  end
  
  def handle_error(error)
    @message.update!(
      conversation_state: STATES[:error],
      error: error.message
    )
    
    broadcast_state_change(STATES[:error], {
      error: error.message,
      recoverable: can_recover?(error)
    })
  end
  
  private
  
  def broadcast_state_change(new_state, details = {})
    ActionCable.server.broadcast("app_#{@message.app.id}_chat", {
      action: 'conversation_state_changed',
      message_id: @message.id,
      old_state: @message.conversation_state_was,
      new_state: new_state,
      timestamp: Time.current.iso8601,
      **details
    })
  end
  
  def can_recover?(error)
    error.is_a?(Timeout::Error) || error.message.include?('retry')
  end
end
```

### Client-Side Parallel Execution Monitor

```javascript
// app/javascript/controllers/parallel_tool_monitor_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["status", "progress", "timeline", "summary"]
  static values = { batchId: Number }
  
  connect() {
    this.toolStatuses = new Map()
    this.startTime = Date.now()
    this.setupWebSocket()
  }
  
  setupWebSocket() {
    // Subscribe to tool execution updates
    this.subscription = consumer.subscriptions.create(
      { channel: "ToolExecutionChannel", message_id: this.messageId },
      {
        received: (data) => this.handleUpdate(data)
      }
    )
  }
  
  handleUpdate(data) {
    switch(data.action) {
      case 'batch_execution_started':
        this.initializeBatch(data)
        break
      case 'tool_started':
        this.markToolStarted(data)
        break
      case 'tool_completed':
        this.markToolCompleted(data)
        break
      case 'tool_failed':
        this.markToolFailed(data)
        break
      case 'tool_timeout':
        this.markToolTimeout(data)
        break
      case 'batch_progress':
        this.updateBatchProgress(data)
        break
      case 'batch_timeout':
        this.handleBatchTimeout(data)
        break
    }
  }
  
  initializeBatch(data) {
    this.statusTarget.textContent = `Executing ${data.total_tools} tools in parallel...`
    this.progressTarget.innerHTML = this.createProgressBar(0)
    
    // Create timeline visualization
    this.timelineTarget.innerHTML = this.createTimeline(data.total_tools)
  }
  
  markToolStarted(data) {
    const toolElement = this.timelineTarget.querySelector(`[data-tool-index="${data.tool_index}"]`)
    if (toolElement) {
      toolElement.classList.add('executing')
      toolElement.querySelector('.status').textContent = '⚡ Running'
    }
    
    this.updateParallelCount(data.parallel_count)
  }
  
  markToolCompleted(data) {
    const toolElement = this.timelineTarget.querySelector(`[data-tool-index="${data.tool_index}"]`)
    if (toolElement) {
      toolElement.classList.remove('executing')
      toolElement.classList.add(data.success ? 'completed' : 'failed')
      toolElement.querySelector('.status').textContent = data.success ? '✓' : '✗'
      toolElement.querySelector('.time').textContent = `${data.execution_time.toFixed(1)}s`
    }
  }
  
  updateBatchProgress(data) {
    const { stats } = data
    const progressPct = Math.round(stats.progress_percentage)
    
    this.progressTarget.innerHTML = this.createProgressBar(progressPct)
    
    this.summaryTarget.innerHTML = `
      <div class="parallel-stats">
        <span class="stat completed">✓ ${stats.completed}</span>
        <span class="stat executing">⚡ ${stats.executing}</span>
        <span class="stat pending">⏳ ${stats.pending}</span>
        <span class="stat failed">✗ ${stats.failed}</span>
      </div>
      <div class="time-estimate">
        ETA: ${this.formatTime(data.estimated_completion)}
      </div>
    `
  }
  
  createProgressBar(percentage) {
    return `
      <div class="progress-bar-wrapper">
        <div class="progress-bar" style="width: ${percentage}%">
          <span class="progress-text">${percentage}%</span>
        </div>
      </div>
    `
  }
  
  createTimeline(totalTools) {
    let html = '<div class="tool-timeline">'
    for (let i = 0; i < totalTools; i++) {
      html += `
        <div class="tool-item" data-tool-index="${i}">
          <span class="status">⏳</span>
          <span class="time"></span>
        </div>
      `
    }
    html += '</div>'
    return html
  }
  
  updateParallelCount(count) {
    this.element.querySelector('.parallel-indicator').textContent = 
      `${count} tools executing in parallel`
  }
}
```

## Implementation Roadmap

### Phase 1: Foundation (Week 1)
- [ ] Create database schema for tool execution tracking
- [ ] Implement `ToolExecutionJob` and `ToolCallBatch` models
- [ ] Create `ToolExecutionDispatcher` service
- [ ] Setup background job infrastructure (Sidekiq queues)
- [ ] Create `ToolExecutionChannel` 
- [ ] Enhance `AppBuilderV5` with streaming methods
- [ ] Basic client-side tool progress controller
- [ ] Database optimizations for real-time updates

### Phase 2: Enhanced Streaming (Week 2)
- [ ] Implement `StreamingToolExecutor` for all major tools
- [ ] Add granular progress tracking for file operations
- [ ] Real-time image generation progress
- [ ] Web search and API call progress streaming

### Phase 3: Advanced UX (Week 3)
- [ ] Beautiful progress animations and transitions
- [ ] User control features (pause/resume/cancel)
- [ ] Performance dashboard with metrics
- [ ] Error handling and recovery UI

### Phase 4: Polish & Optimization (Week 4)
- [ ] Performance testing and optimization
- [ ] Error handling and edge cases
- [ ] Mobile responsive design
- [ ] Comprehensive testing

## Benefits & Impact

### User Experience Benefits:
- 🎬 **Netflix-grade UX**: Smooth, professional real-time feedback
- 🔍 **Full Transparency**: Users see exactly what's happening
- ⚡ **Perceived Performance**: Feels faster even when execution time is same
- 🎮 **Interactive Control**: Users can pause, resume, or cancel operations
- 📊 **Rich Insights**: Detailed metrics and performance data

### Technical Benefits:
- 🏗️ **Builds on Existing Infrastructure**: 80% of code already exists
- 📈 **Scalable Architecture**: WebSocket channels scale horizontally
- 🔧 **Maintainable**: Clean separation of concerns
- 🧪 **Testable**: Each component can be unit tested
- 🚀 **Future-Ready**: Foundation for advanced features

### Business Benefits:
- 💯 **Premium Feel**: Differentiates from competitors 
- 📱 **Engagement**: Users stay engaged during long operations
- 🎯 **Trust**: Transparency builds user confidence
- 🔄 **Retention**: Better UX improves user retention

## Risk Assessment & Mitigation

### Technical Risks:
1. **WebSocket Connection Issues**
   - *Mitigation*: Graceful fallback to current system
   - *Detection*: Connection health monitoring
   - *Recovery*: Automatic reconnection with state sync

2. **Performance Impact**
   - *Mitigation*: Efficient broadcasting (only active users)
   - *Detection*: Performance monitoring and alerts
   - *Recovery*: Circuit breaker patterns

3. **Complexity Increase**
   - *Mitigation*: Incremental rollout, comprehensive testing
   - *Detection*: Code quality metrics
   - *Recovery*: Feature flags for quick disable

### Business Risks:
1. **Development Time**
   - *Mitigation*: Leverages existing infrastructure (80% done)
   - *Timeline*: 4-week phased approach
   - *ROI*: Significant UX improvement for reasonable investment

## Success Metrics

### Performance Metrics:
- WebSocket connection success rate: >99%
- Message delivery latency: <100ms
- UI update responsiveness: <50ms
- Memory usage increase: <10%

### User Experience Metrics:
- User engagement during tool execution: +200%
- Perceived performance rating: +150%
- Support tickets for "is it working?": -80%
- User satisfaction scores: +25%

## Conclusion

Option 4 represents a **high-impact, moderate-risk** enhancement that transforms OverSkill's tool execution UX from good to **exceptional**. The existing infrastructure makes this feasible with a reasonable investment, and the phased approach ensures manageable implementation.

**Recommendation**: ✅ **PROCEED** with Option 4 implementation using the phased approach outlined above.

The combination of existing ActionCable infrastructure, proven real-time UI patterns, and clear implementation strategy makes this the ideal time to elevate OverSkill's UX to Netflix/Uber quality standards.

---

*This strategy leverages OverSkill's existing ActionCable, Stimulus, and Turbo infrastructure while adding the granular real-time features that make the difference between good and exceptional user experience.*