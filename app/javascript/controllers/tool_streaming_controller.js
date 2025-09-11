import { Controller } from "@hotwired/stimulus"
import consumer from "../channels/consumer"

// Handles real-time tool streaming updates via ActionCable
export default class extends Controller {
  static values = { 
    messageId: Number,
    appId: Number 
  }
  
  connect() {
    console.log("[ToolStreaming] Connecting for message", this.messageIdValue)
    
    // Subscribe to ChatProgressChannel for tool updates
    this.subscription = consumer.subscriptions.create(
      {
        channel: "ChatProgressChannel",
        message_id: this.messageIdValue
      },
      {
        connected: () => {
          console.log("[ToolStreaming] Connected to ChatProgressChannel")
        },
        
        disconnected: () => {
          console.log("[ToolStreaming] Disconnected from ChatProgressChannel")
        },
        
        received: (data) => {
          this.handleUpdate(data)
        }
      }
    )
  }
  
  disconnect() {
    if (this.subscription) {
      this.subscription.unsubscribe()
    }
  }
  
  handleUpdate(data) {
    console.log("[ToolStreaming] Received update:", data)
    
    switch(data.action) {
      case 'tool_status_update':
        this.handleToolStatusUpdate(data)
        break
      case 'tool_progress_update':
        this.handleToolProgressUpdate(data)
        break
      case 'conversation_flow_update':
        this.handleConversationFlowUpdate(data)
        break
      case 'incremental_tool_update':
        this.handleIncrementalToolUpdate(data)
        break
      default:
        console.log("[ToolStreaming] Unknown action:", data.action)
    }
  }
  
  handleToolStatusUpdate(data) {
    // The status update will be handled by Turbo Streams replacing the partial
    // This is just for any additional client-side logic needed
    
    // Find tool elements and add visual feedback
    const toolElements = this.element.querySelectorAll('[data-tool-name]')
    toolElements.forEach(toolEl => {
      const toolName = toolEl.dataset.toolName
      const filePath = toolEl.dataset.filePath
      
      // Find matching tool in conversation_flow
      if (data.conversation_flow) {
        const tool = this.findToolInFlow(data.conversation_flow, toolName, filePath)
        if (tool) {
          this.updateToolElement(toolEl, tool.status)
        }
      }
    })
  }
  
  handleToolProgressUpdate(data) {
    // Handle granular progress updates if needed
    console.log("[ToolStreaming] Tool progress:", data.progress, data.message)
    
    // Could update a progress bar or status text here
    if (data.tool_index !== undefined) {
      const progressEl = this.element.querySelector(`[data-tool-index="${data.tool_index}"] .progress-text`)
      if (progressEl && data.message) {
        progressEl.textContent = data.message
      }
    }
  }
  
  handleConversationFlowUpdate(data) {
    // The main update happens via Turbo Streams
    // This is for any additional animations or effects
    
    // Add pulse animation to updated tools
    const updatedTools = this.element.querySelectorAll('.tool-item[data-status="running"]')
    updatedTools.forEach(tool => {
      tool.classList.add('animate-pulse')
    })
  }
  
  handleIncrementalToolUpdate(data) {
    console.log("[ToolStreaming] Incremental tool update:", data.execution_id, data.tool_index, data.status)
    
    // Handle incremental tool status updates for the V2 streaming system
    // The main UI update is handled by Turbo Streams, but we can add
    // client-side visual effects here
    
    if (data.tool_index !== undefined) {
      // Find the specific tool element by execution ID and tool index
      const toolSelector = `[data-execution-id="${data.execution_id}"][data-tool-index="${data.tool_index}"]`
      const toolElement = this.element.querySelector(toolSelector)
      
      if (toolElement) {
        this.updateToolElement(toolElement, data.status)
        
        // Add status-specific animations
        if (data.status === 'complete') {
          toolElement.classList.add('animate-pulse')
          setTimeout(() => {
            toolElement.classList.remove('animate-pulse')
          }, 1000)
        } else if (data.status === 'running') {
          toolElement.classList.add('animate-pulse')
        }
      }
    }
    
    // Update progress text if provided
    if (data.progress_text && data.tool_index !== undefined) {
      const progressSelector = `[data-execution-id="${data.execution_id}"][data-tool-index="${data.tool_index}"] .progress-text`
      const progressEl = this.element.querySelector(progressSelector)
      if (progressEl) {
        progressEl.textContent = data.progress_text
      }
    }
  }
  
  findToolInFlow(flow, toolName, filePath) {
    for (const item of flow) {
      if (item.type === 'tools' && (item.tools || item.calls)) {
        const toolsArray = item.tools || item.calls || []
        for (const tool of toolsArray) {
          if (tool.name === toolName && tool.file_path === filePath) {
            return tool
          }
        }
      }
    }
    return null
  }
  
  updateToolElement(element, status) {
    // Remove all status classes
    element.classList.remove('tool-running', 'tool-complete', 'tool-error')
    
    // Add appropriate status class
    switch(status) {
      case 'running':
        element.classList.add('tool-running')
        // Add spinner icon
        const spinner = element.querySelector('.status-icon')
        if (spinner) {
          spinner.innerHTML = '<i class="fas fa-spinner fa-spin text-yellow-500"></i>'
        }
        break
      case 'complete':
        element.classList.add('tool-complete')
        // Add check icon
        const check = element.querySelector('.status-icon')
        if (check) {
          check.innerHTML = '<i class="fas fa-check-circle text-green-500"></i>'
        }
        break
      case 'error':
        element.classList.add('tool-error')
        // Add error icon
        const error = element.querySelector('.status-icon')
        if (error) {
          error.innerHTML = '<i class="fas fa-times-circle text-red-500"></i>'
        }
        break
    }
  }
}