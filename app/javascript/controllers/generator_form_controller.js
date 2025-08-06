import { Controller } from "@hotwired/stimulus"
import { post } from "@rails/request.js"

export default class extends Controller {
  static targets = ["form", "submitButton", "spinner"]
  
  async submit(event) {
    event.preventDefault()
    
    const form = event.target
    const formData = new FormData(form)
    
    // Show loading state
    this.showLoading()
    
    try {
      const response = await post(form.action, {
        body: formData,
        headers: {
          "Accept": "application/json"
        }
      })
      
      const data = await response.json
      
      if (response.status === 401 || (response.ok && data.requires_auth)) {
        // User needs to authenticate - trigger the auth modal
        this.hideLoading()
        
        // Dispatch event to open auth modal with the prompt
        const authModal = document.querySelector('[data-controller="auth-modal"]')
        if (authModal) {
          const controller = this.application.getControllerForElementAndIdentifier(authModal, 'auth-modal')
          controller.open({ detail: { prompt: data.prompt || formData.get('prompt') || formData.get('custom_prompt') } })
        }
      } else if (response.ok && data.redirect_url) {
        // Success - redirect to the app editor
        window.location.href = data.redirect_url
      } else {
        // Handle errors
        this.hideLoading()
        this.showError(data.error || "An error occurred. Please try again.")
      }
    } catch (error) {
      console.error("Form submission error:", error)
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