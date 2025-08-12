// Stimulus controller for the approval panel interactions
import { Controller } from "@hotwired/stimulus"
import consumer from "../channels/consumer"

export default class extends Controller {
  static targets = [
    "changeCheckbox",
    "selectedCount", 
    "approveButton",
    "changesList"
  ]
  
  static values = {
    callbackId: String,
    chatMessageId: Number
  }
  
  connect() {
    this.updateSelectionCount()
    this.subscription = this.subscribeToChannel()
  }
  
  disconnect() {
    if (this.subscription) {
      this.subscription.unsubscribe()
    }
  }
  
  // Subscribe to the chat channel for this message
  subscribeToChannel() {
    return consumer.subscriptions.create(
      { 
        channel: "ChatChannel",
        chat_message_id: this.chatMessageIdValue
      },
      {
        received: (data) => this.handleChannelData(data)
      }
    )
  }
  
  // Handle channel data
  handleChannelData(data) {
    if (data.action === 'approval_response' && data.callback_id === this.callbackIdValue) {
      this.handleApprovalResponse(data)
    }
  }
  
  // Select all checkboxes
  selectAll(event) {
    event.preventDefault()
    this.changeCheckboxTargets.forEach(checkbox => {
      checkbox.checked = true
    })
    this.updateSelectionCount()
  }
  
  // Deselect all checkboxes
  deselectAll(event) {
    event.preventDefault()
    this.changeCheckboxTargets.forEach(checkbox => {
      checkbox.checked = false
    })
    this.updateSelectionCount()
  }
  
  // Update the selected count display
  updateSelectionCount() {
    const selectedCount = this.changeCheckboxTargets.filter(cb => cb.checked).length
    this.selectedCountTarget.textContent = selectedCount
    
    // Enable/disable approve button based on selection
    if (this.hasApproveButtonTarget) {
      this.approveButtonTarget.disabled = selectedCount === 0
      if (selectedCount === 0) {
        this.approveButtonTarget.classList.add('opacity-50', 'cursor-not-allowed')
      } else {
        this.approveButtonTarget.classList.remove('opacity-50', 'cursor-not-allowed')
      }
    }
  }
  
  // Approve selected changes
  approveSelected(event) {
    event.preventDefault()
    
    const selectedFiles = this.changeCheckboxTargets
      .filter(cb => cb.checked)
      .map(cb => cb.dataset.filePath)
    
    if (selectedFiles.length === 0) {
      return
    }
    
    // Show loading state
    this.setLoadingState(true)
    
    // Send approval to server
    this.subscription.perform('approve_changes', {
      callback_id: this.callbackIdValue,
      approved_files: selectedFiles
    })
  }
  
  // Reject all changes
  rejectAll(event) {
    event.preventDefault()
    
    // Show loading state
    this.setLoadingState(true)
    
    // Send rejection to server
    this.subscription.perform('reject_changes', {
      callback_id: this.callbackIdValue
    })
  }
  
  // Set loading state for the panel
  setLoadingState(loading) {
    if (loading) {
      // Disable all inputs
      this.changeCheckboxTargets.forEach(cb => cb.disabled = true)
      
      // Update button states
      if (this.hasApproveButtonTarget) {
        const originalText = this.approveButtonTarget.innerHTML
        this.approveButtonTarget.dataset.originalText = originalText
        this.approveButtonTarget.innerHTML = `
          <svg class="animate-spin h-4 w-4 inline-block mr-1" fill="none" viewBox="0 0 24 24">
            <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
            <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
          </svg>
          Processing...
        `
        this.approveButtonTarget.disabled = true
      }
      
      // Add loading overlay
      this.element.classList.add('opacity-75')
    } else {
      // Re-enable inputs
      this.changeCheckboxTargets.forEach(cb => cb.disabled = false)
      
      // Restore button states
      if (this.hasApproveButtonTarget && this.approveButtonTarget.dataset.originalText) {
        this.approveButtonTarget.innerHTML = this.approveButtonTarget.dataset.originalText
        this.approveButtonTarget.disabled = false
      }
      
      // Remove loading overlay
      this.element.classList.remove('opacity-75')
    }
  }
  
  // Handle approval response from server
  handleApprovalResponse(data) {
    if (data.success) {
      // Success animation
      this.element.classList.add('animate-fade-out')
      
      setTimeout(() => {
        // Replace with success message
        this.element.innerHTML = `
          <div class="rounded-lg bg-green-50 dark:bg-green-900/20 p-4">
            <div class="flex items-center space-x-3">
              <svg class="w-6 h-6 text-green-500" fill="currentColor" viewBox="0 0 20 20">
                <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"/>
              </svg>
              <div>
                <h3 class="text-sm font-medium text-green-800 dark:text-green-200">
                  Changes Applied Successfully
                </h3>
                <p class="text-sm text-green-600 dark:text-green-400">
                  ${data.message || 'Your selected changes have been applied.'}
                </p>
              </div>
            </div>
          </div>
        `
      }, 300)
    } else {
      // Error handling
      this.setLoadingState(false)
      this.showError(data.error || 'Failed to apply changes')
    }
  }
  
  // Show error message
  showError(message) {
    const errorDiv = document.createElement('div')
    errorDiv.className = 'mt-3 p-3 bg-red-50 dark:bg-red-900/20 rounded-md animate-shake'
    errorDiv.innerHTML = `
      <p class="text-sm text-red-700 dark:text-red-300">
        <svg class="w-4 h-4 inline-block mr-1" fill="currentColor" viewBox="0 0 20 20">
          <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd"/>
        </svg>
        ${message}
      </p>
    `
    
    this.element.appendChild(errorDiv)
    
    // Remove error after 5 seconds
    setTimeout(() => errorDiv.remove(), 5000)
  }
}