import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.resize()
    
    // Listen for Turbo events to handle form replacement
    this.handleTurboLoad = this.handleTurboLoad.bind(this)
    document.addEventListener('turbo:load', this.handleTurboLoad)
    document.addEventListener('turbo:frame-load', this.handleTurboLoad)
  }
  
  disconnect() {
    document.removeEventListener('turbo:load', this.handleTurboLoad)
    document.removeEventListener('turbo:frame-load', this.handleTurboLoad)
  }
  
  handleTurboLoad() {
    // Ensure proper height after Turbo replaces content
    if (this.element && this.element.isConnected) {
      this.element.style.height = 'auto'
      this.resize()
    }
  }

  resize() {
    // Ensure element exists and is connected to DOM
    if (!this.element || !this.element.isConnected) return
    
    this.element.style.height = 'auto'
    this.element.style.height = this.element.scrollHeight + 'px'
  }

  submit(event) {
    if (event.key === 'Enter' && (event.metaKey || event.ctrlKey)) {
      event.preventDefault()
      const form = this.element.form
      
      // Store current value before submit
      const currentValue = this.element.value
      
      // Submit the form
      form.requestSubmit()
      
      // Reset the textarea height after a small delay to prevent layout jump
      setTimeout(() => {
        this.element.style.height = 'auto'
        this.resize()
      }, 10)
    }
  }
}