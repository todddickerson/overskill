import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form", "submitButton", "spinner"]
  
  async submit(event) {
    event.preventDefault()
    
    const form = event.target
    const formData = new FormData(form)
    
    // Show loading state
    this.showLoading()
    
    try {
      // Use native fetch for better error handling
      const response = await fetch(form.action, {
        method: 'POST',
        body: formData,
        headers: {
          'Accept': 'application/json',
          'X-Requested-With': 'XMLHttpRequest'
        },
        credentials: 'same-origin'
      })
      
      console.log("Response status:", response.status)
      
      // Check for 401 before trying to parse JSON
      if (response.status === 401) {
        // User needs to authenticate - trigger the auth modal
        this.hideLoading()
        
        // Try to get the prompt from the response if possible
        let promptData = { prompt: formData.get('prompt') || formData.get('custom_prompt') }
        try {
          const data = await response.json()
          if (data.prompt) {
            promptData.prompt = data.prompt
          }
        } catch (e) {
          // If JSON parsing fails, use the form data
          console.log("Could not parse 401 response JSON, using form data for prompt")
        }
        
        console.log("Opening auth modal with prompt:", promptData.prompt)
        
        // Open auth modal using a custom event
        const event = new CustomEvent('auth-modal:open', {
          detail: promptData,
          bubbles: true
        })
        document.dispatchEvent(event)
        return
      }
      
      // Parse JSON response
      const data = await response.json()
      
      if (response.ok && data.redirect_url) {
        // Success - redirect to the app editor
        window.location.href = data.redirect_url
      } else {
        // Handle errors
        this.hideLoading()
        this.showError(data.error || "An error occurred. Please try again.")
      }
    } catch (error) {
      console.error("Form submission error:", error)
      console.error("Error details:", error.message, error.stack)
      this.hideLoading()
      this.showError("An error occurred. Please try again.")
    }
  }
  
  showLoading() {
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.disabled = true
      const originalText = this.submitButtonTarget.textContent
      this.submitButtonTarget.dataset.originalText = originalText
      this.submitButtonTarget.textContent = "Creating..."
    }
    
    if (this.hasSpinnerTarget) {
      this.spinnerTarget.classList.remove("hidden")
    }
  }
  
  hideLoading() {
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.disabled = false
      const originalText = this.submitButtonTarget.dataset.originalText
      if (originalText) {
        this.submitButtonTarget.textContent = originalText
      }
    }
    
    if (this.hasSpinnerTarget) {
      this.spinnerTarget.classList.add("hidden")
    }
  }
  
  showError(message) {
    // You can customize this to show errors in a nicer way
    alert(message)
  }
}