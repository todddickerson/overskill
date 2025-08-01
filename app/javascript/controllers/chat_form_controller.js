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
    
    document.addEventListener('turbo:submit-start', this.boundBeforeSubmit)
    document.addEventListener('turbo:submit-end', this.boundAfterSubmit)
    document.addEventListener('turbo:before-stream-render', this.boundStreamRender)
    
    // Initialize timeout tracking
    this.processingTimeout = null
    this.maxProcessingTime = 5 * 60 * 1000 // 5 minutes max processing time
  }
  
  disconnect() {
    document.removeEventListener('turbo:submit-start', this.boundBeforeSubmit)
    document.removeEventListener('turbo:submit-end', this.boundAfterSubmit)
    document.removeEventListener('turbo:before-stream-render', this.boundStreamRender)
    
    // Clear any existing timeout
    if (this.processingTimeout) {
      clearTimeout(this.processingTimeout)
    }
  }
  
  checkProcessingState() {
    // Check if there's any assistant message with status 'planning', 'executing', or 'generating'
    const processingMessages = document.querySelectorAll('[data-message-status="planning"], [data-message-status="executing"], [data-message-status="generating"]')
    this.processingValue = processingMessages.length > 0
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
    // Disable textarea
    if (this.hasTextareaTarget) {
      this.textareaTarget.disabled = true
      this.textareaTarget.placeholder = "Waiting for response..."
      this.textareaTarget.classList.add('opacity-50', 'cursor-not-allowed')
    }
    
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
    // Enable textarea
    if (this.hasTextareaTarget) {
      this.textareaTarget.disabled = false
      this.textareaTarget.placeholder = "Tell me what you'd like to change..."
      this.textareaTarget.classList.remove('opacity-50', 'cursor-not-allowed')
      this.textareaTarget.focus()
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
    console.log('Keydown event:', event.key, 'Meta:', event.metaKey, 'Ctrl:', event.ctrlKey)
    
    // Check for cmd+enter or ctrl+enter
    if ((event.metaKey || event.ctrlKey) && event.key === 'Enter') {
      console.log('Cmd+Enter detected, submitting...')
      event.preventDefault()
      this.submit(event)
    }
  }
  
  // Handle form submission
  submit(event) {
    console.log('Submit called, processing:', this.processingValue)
    console.log('Has textarea target:', this.hasTextareaTarget)
    console.log('Textarea value:', this.hasTextareaTarget ? this.textareaTarget.value : 'N/A')
    console.log('Textarea element:', this.hasTextareaTarget ? this.textareaTarget : 'N/A')
    
    // Only prevent default if it's a form submission event
    if (event && event.type === 'submit') {
      event.preventDefault()
    }
    
    // Don't submit if already processing
    if (this.processingValue) {
      console.log('Already processing, skipping submit')
      return
    }
    
    // Don't submit if textarea is empty or doesn't exist
    if (!this.hasTextareaTarget || !this.textareaTarget.value.trim()) {
      console.log('No textarea or empty value')
      console.log('Textarea targets found:', this.element.querySelectorAll('[data-chat-form-target="textarea"]').length)
      return
    }
    
    console.log('Submitting form...')
    console.log('Form element:', this.element)
    console.log('Submit target:', this.hasSubmitTarget ? this.submitTarget : 'N/A')
    
    // Try multiple submission methods
    try {
      // Method 1: Use requestSubmit if available (modern browsers)
      if (this.element.tagName === 'FORM') {
        console.log('Using direct form submission')
        if (this.element.requestSubmit) {
          console.log('Using requestSubmit')
          this.element.requestSubmit()
        } else {
          console.log('Fallback to submit()')
          this.element.submit()
        }
      } else {
        // Method 2: Find the form and submit it
        const form = this.element.closest('form') || this.element.querySelector('form')
        if (form) {
          console.log('Found form via search:', form)
          if (form.requestSubmit) {
            console.log('Using requestSubmit on found form')
            form.requestSubmit()
          } else {
            console.log('Using submit() on found form')
            form.submit()
          }
        } else {
          console.error('Could not find form element')
        }
      }
    } catch (error) {
      console.error('Form submission error:', error)
      // Last resort: try clicking the submit button
      if (this.hasSubmitTarget) {
        console.log('Trying submit button click as fallback')
        this.submitTarget.click()
      }
    }
  }
}