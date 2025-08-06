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
    console.log('Keydown event:', event.key, 'Meta:', event.metaKey, 'Ctrl:', event.ctrlKey)
    
    // Check for cmd+enter or ctrl+enter
    if ((event.metaKey || event.ctrlKey) && event.key === 'Enter') {
      console.log('Cmd+Enter detected, triggering form submission...')
      event.preventDefault() // Prevent default textarea behavior
      
      // Find the form element and submit it
      const form = this.element
      if (form && form.tagName === 'FORM') {
        console.log('Submitting form via requestSubmit...')
        if (form.requestSubmit) {
          form.requestSubmit()
        } else {
          // Fallback for older browsers
          const submitButton = this.hasSubmitTarget ? this.submitTarget : form.querySelector('[type="submit"]')
          if (submitButton) {
            submitButton.click()
          } else {
            form.submit()
          }
        }
      }
    }
  }
  
  // Handle submit button click
  handleSubmitClick(event) {
    console.log('Submit button clicked')
    
    // Don't submit if already processing
    if (this.processingValue) {
      console.log('Already processing, preventing submission')
      event.preventDefault()
      return
    }
    
    // Don't submit if no visible textarea has content
    const visibleTextarea = this.textareaTargets.find(textarea => {
      // Check if the textarea is in a visible container
      const desktopContainer = textarea.closest('.hidden.lg\\:block')
      const mobileContainer = textarea.closest('.lg\\:hidden')
      
      // Determine if visible based on screen size
      const isDesktop = window.innerWidth >= 1024
      const isVisible = isDesktop ? desktopContainer : mobileContainer
      
      console.log(`Checking textarea visibility - isDesktop: ${isDesktop}, hasValue: ${!!textarea.value.trim()}`)
      return isVisible && textarea.value.trim()
    })
    
    if (!visibleTextarea) {
      console.log('No visible textarea with content, preventing submission')
      event.preventDefault()
      return
    }
    
    console.log('Submit validation passed, allowing form to submit')
    // Let the form submit naturally since type="submit" is set
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
    
    // Don't submit if no visible textarea has content
    const visibleTextarea = this.textareaTargets.find(textarea => {
      // Check if the textarea is in a visible container
      const desktopContainer = textarea.closest('.hidden.lg\\:block')
      const mobileContainer = textarea.closest('.lg\\:hidden')
      
      // Determine if visible based on screen size
      const isDesktop = window.innerWidth >= 1024
      const isVisible = isDesktop ? desktopContainer : mobileContainer
      
      console.log(`Checking textarea visibility - isDesktop: ${isDesktop}, hasValue: ${!!textarea.value.trim()}, value: "${textarea.value}"`)
      return isVisible && textarea.value.trim()
    })
    
    if (!visibleTextarea) {
      console.log('No visible textarea with content, preventing submission')
      console.log('All textarea values:', this.textareaTargets.map(t => t.value))
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