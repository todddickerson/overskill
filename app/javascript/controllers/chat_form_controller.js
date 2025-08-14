import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["textarea", "submit"]
  static values = { processing: Boolean }
  
  connect() {
    // Check if there's an assistant message being generated
    this.checkProcessingState()
    
    // Listen for Turbo events
    this.boundBeforeSubmit = this.beforeSubmit.bind(this)
    this.boundAfterSubmit = this.afterSubmit.bind(this)
    this.boundStreamRender = this.handleStreamRender.bind(this)
    this.boundHandleError = this.handleError.bind(this)
    this.boundHandleComplete = this.handleComplete.bind(this)
    
    document.addEventListener('turbo:submit-start', this.boundBeforeSubmit)
    document.addEventListener('turbo:submit-end', this.boundAfterSubmit)
    document.addEventListener('turbo:before-stream-render', this.boundStreamRender)
    document.addEventListener('chat:error', this.boundHandleError)
    document.addEventListener('chat:complete', this.boundHandleComplete)
    
    // Initialize timeout tracking
    this.processingTimeout = null
    this.maxProcessingTime = 5 * 60 * 1000 // 5 minutes max processing time
  }
  
  disconnect() {
    document.removeEventListener('turbo:submit-start', this.boundBeforeSubmit)
    document.removeEventListener('turbo:submit-end', this.boundAfterSubmit)
    document.removeEventListener('turbo:before-stream-render', this.boundStreamRender)
    document.removeEventListener('chat:error', this.boundHandleError)
    document.removeEventListener('chat:complete', this.boundHandleComplete)
    
    // Clear any existing timeout
    if (this.processingTimeout) {
      clearTimeout(this.processingTimeout)
    }
  }
  
  checkProcessingState() {
    // Check if there's any assistant message with status 'planning', 'executing', or 'generating'
    const processingMessages = document.querySelectorAll('[data-message-status="planning"], [data-message-status="executing"], [data-message-status="generating"]')
    
    // Also check for failed or completed messages to ensure we're not stuck
    const failedMessages = document.querySelectorAll('[data-message-status="failed"]')
    const completedMessages = document.querySelectorAll('[data-message-status="completed"]')
    
    // If we have failed or completed messages and no processing messages, we're not processing
    if ((failedMessages.length > 0 || completedMessages.length > 0) && processingMessages.length === 0) {
      this.processingValue = false
    } else {
      this.processingValue = processingMessages.length > 0
    }
  }
  
  handleError(event) {
    console.log('Chat error event received:', event.detail)
    // Force enable the form when an error occurs
    this.processingValue = false
    this.enable()
  }
  
  handleComplete(event) {
    console.log('Chat complete event received')
    // Enable the form when generation is complete
    this.processingValue = false
    this.enable()
  }
  
  beforeSubmit(event) {
    // Only handle our form
    if (!event.target.contains(this.element)) return
    
    this.processingValue = true
  }
  
  afterSubmit(event) {
    // Reset after a delay to ensure the new message is rendered
    setTimeout(() => {
      this.checkProcessingState()
    }, 100)
  }
  
  handleStreamRender(event) {
    // Check processing state after each Turbo Stream update
    setTimeout(() => {
      this.checkProcessingState()
    }, 50)
  }
  
  processingValueChanged() {
    if (this.processingValue) {
      this.disable()
      this.startProcessingTimeout()
    } else {
      this.enable()
      this.clearProcessingTimeout()
    }
  }
  
  startProcessingTimeout() {
    // Clear any existing timeout
    this.clearProcessingTimeout()
    
    // Set a new timeout
    this.processingTimeout = setTimeout(() => {
      console.warn('Processing timeout reached, enabling form')
      this.handleProcessingTimeout()
    }, this.maxProcessingTime)
  }
  
  clearProcessingTimeout() {
    if (this.processingTimeout) {
      clearTimeout(this.processingTimeout)
      this.processingTimeout = null
    }
  }
  
  handleProcessingTimeout() {
    // Force enable the form after timeout
    this.processingValue = false
    
    // Find any stuck messages and update their display
    const processingMessages = document.querySelectorAll('[data-message-status="planning"], [data-message-status="executing"], [data-message-status="generating"]')
    processingMessages.forEach(message => {
      const contentElement = message.querySelector('.message-content')
      if (contentElement) {
        // Update the message to show timeout error
        contentElement.innerHTML = `
          <div class="text-red-600 dark:text-red-400">
            <i class="fas fa-exclamation-circle mr-2"></i>
            Request timed out. Please try again with a simpler request.
          </div>
        `
      }
      // Update the status to failed
      message.setAttribute('data-message-status', 'failed')
    })
  }
  
  disable() {
    // Disable all textareas
    this.textareaTargets.forEach(textarea => {
      textarea.disabled = true
      textarea.placeholder = "Waiting for response..."
      textarea.classList.add('opacity-50', 'cursor-not-allowed')
    })
    
    // Disable submit button
    if (this.hasSubmitTarget) {
      this.submitTarget.disabled = true
      this.submitTarget.classList.add('opacity-50', 'cursor-not-allowed')
      
      // Change icon to spinner
      const icon = this.submitTarget.querySelector('i')
      if (icon) {
        icon.classList.remove('fa-arrow-up')
        icon.classList.add('fa-spinner', 'fa-spin')
      }
    }
  }
  
  enable() {
    // Enable all textareas
    this.textareaTargets.forEach(textarea => {
      textarea.disabled = false
      const isDesktop = textarea.closest('.hidden')
      textarea.placeholder = isDesktop ? "Ask AI to help with your app..." : "Ask Overskill..."
      textarea.classList.remove('opacity-50', 'cursor-not-allowed')
    })
    
    // Focus the visible textarea
    const visibleTextarea = this.textareaTargets.find(textarea => 
      !textarea.closest('.hidden') && !textarea.closest('.lg\\:hidden')
    )
    if (visibleTextarea) {
      visibleTextarea.focus()
    }
    
    // Enable submit button
    if (this.hasSubmitTarget) {
      this.submitTarget.disabled = false
      this.submitTarget.classList.remove('opacity-50', 'cursor-not-allowed')
      
      // Change icon back to arrow
      const icon = this.submitTarget.querySelector('i')
      if (icon) {
        icon.classList.remove('fa-spinner', 'fa-spin')
        icon.classList.add('fa-arrow-up')
      }
    }
  }
  
  // Handle keyboard shortcuts
  handleKeydown(event) {
    // console.log('Keydown event:', event.key, 'Meta:', event.metaKey, 'Ctrl:', event.ctrlKey)
    
    // Check for cmd+enter (Mac) or ctrl+enter (Windows/Linux)
    // On Mac, we want to accept ONLY metaKey (Cmd), not ctrlKey
    // On Windows/Linux, we accept ctrlKey
    // However, we'll be flexible and accept either to ensure it works
    const isSubmitShortcut = (event.metaKey || event.ctrlKey) && event.key === 'Enter'
    
    if (isSubmitShortcut) {
      console.log('Cmd/Ctrl+Enter detected, triggering form submission...')
      event.preventDefault() // Prevent default textarea behavior
      event.stopPropagation() // Stop event from bubbling
      
      // Don't submit if already processing
      if (this.processingValue) {
        console.log('Already processing, ignoring keyboard shortcut')
        return
      }
      
      // Check if the current textarea has content
      const currentTextarea = event.target
      if (!currentTextarea.value.trim()) {
        console.log('No content in textarea, ignoring keyboard shortcut')
        return
      }
      
      // Find the form element and submit it
      const form = this.element
      if (form && form.tagName === 'FORM') {
        console.log('Submitting form via requestSubmit...')
        
        // Use requestSubmit for proper form validation and Turbo handling
        if (form.requestSubmit) {
          // Find the submit button and use it for requestSubmit
          const submitButton = this.hasSubmitTarget ? this.submitTarget : form.querySelector('[type="submit"]')
          if (submitButton) {
            form.requestSubmit(submitButton)
          } else {
            form.requestSubmit()
          }
        } else {
          // Fallback for older browsers - click the submit button
          const submitButton = this.hasSubmitTarget ? this.submitTarget : form.querySelector('[type="submit"]')
          if (submitButton) {
            submitButton.click()
          } else {
            // Last resort - direct form submission
            form.submit()
          }
        }
      }
    }
  }
  
  // Handle submit button clicks (mobile button specifically)
  handleSubmitClick(event) {
    console.log('Submit button clicked, processing:', this.processingValue)
    
    // Don't submit if already processing
    if (this.processingValue) {
      console.log('Already processing, ignoring button click')
      event.preventDefault()
      return
    }
    
    // Check if any textarea has content
    const hasContent = this.textareaTargets.some(textarea => textarea.value.trim())
    
    if (!hasContent) {
      console.log('No content to submit, ignoring button click')
      event.preventDefault()
      return
    }
    
    // Trigger form submission
    console.log('Button validation passed, triggering form submission...')
    const form = this.element
    if (form && form.tagName === 'FORM') {
      // Use requestSubmit for proper form validation and Turbo handling
      if (form.requestSubmit) {
        form.requestSubmit(event.currentTarget)
      } else {
        // Fallback for older browsers
        form.submit()
      }
    }
  }

  // Handle form submission
  submit(event) {
    console.log('Submit called, processing:', this.processingValue)
    console.log('Event type:', event ? event.type : 'no event')
    console.log('Form element:', this.element)
    console.log('Textarea targets count:', this.textareaTargets.length)
    this.textareaTargets.forEach((textarea, index) => {
      console.log(`Textarea ${index} value:`, textarea.value)
      console.log(`Textarea ${index} visible:`, !textarea.closest('.hidden'))
    })
    
    // Log form data
    if (this.element && this.element.tagName === 'FORM') {
      const formData = new FormData(this.element)
      console.log('Form data entries:')
      for (let [key, value] of formData.entries()) {
        console.log(`  ${key}: ${value}`)
      }
    }
    
    // Don't submit if already processing
    if (this.processingValue) {
      console.log('Already processing, preventing submission')
      if (event) event.preventDefault()
      return
    }
    
    // Check if any textarea has content (Rails will handle which one to use based on parameter names)
    const hasContent = this.textareaTargets.some(textarea => textarea.value.trim())
    
    if (!hasContent) {
      console.log('No content to submit, preventing submission')
      if (event) event.preventDefault()
      return
    }
    
    console.log('Form validation passed, allowing submission to proceed to Rails...')
    // Set processing state to prevent duplicate submissions
    this.processingValue = true
    
    // Allow the form to submit naturally - don't preventDefault()
    // The form will be submitted by Rails/Turbo automatically
  }
}