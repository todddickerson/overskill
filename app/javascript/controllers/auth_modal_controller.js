import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal", "loginForm", "signupForm", "loginTab", "signupTab", "errorMessage"]
  static values = { 
    show: Boolean,
    prompt: String 
  }
  
  connect() {
    // Show modal if show value is true (set by server)
    if (this.showValue) {
      this.show()
    }
  }
  
  show() {
    this.element.classList.remove("hidden")
    document.body.style.overflow = "hidden" // Prevent background scrolling
  }
  
  close() {
    this.element.classList.add("hidden")
    document.body.style.overflow = "" // Re-enable scrolling
    this.clearErrors()
    
    // Navigate back to generator page
    window.location.href = '/'
  }
  
  switchToLogin(event) {
    event.preventDefault()
    this.showLogin()
  }
  
  switchToSignup(event) {
    event.preventDefault()
    this.showSignup()
  }
  
  showLogin() {
    this.loginFormTarget.classList.remove("hidden")
    this.signupFormTarget.classList.add("hidden")
    this.loginTabTarget.classList.add("border-primary-500", "text-primary-600")
    this.loginTabTarget.classList.remove("border-transparent", "text-gray-500")
    this.signupTabTarget.classList.remove("border-primary-500", "text-primary-600")
    this.signupTabTarget.classList.add("border-transparent", "text-gray-500")
    this.clearErrors()
  }
  
  showSignup() {
    this.signupFormTarget.classList.remove("hidden")
    this.loginFormTarget.classList.add("hidden")
    this.signupTabTarget.classList.add("border-primary-500", "text-primary-600")
    this.signupTabTarget.classList.remove("border-transparent", "text-gray-500")
    this.loginTabTarget.classList.remove("border-primary-500", "text-primary-600")
    this.loginTabTarget.classList.add("border-transparent", "text-gray-500")
    this.clearErrors()
  }
  
  // No need for custom submission handling - let Rails handle it normally
  
  showError(message) {
    if (this.hasErrorMessageTarget) {
      this.errorMessageTarget.textContent = message
      this.errorMessageTarget.classList.remove("hidden")
    }
  }
  
  clearErrors() {
    if (this.hasErrorMessageTarget) {
      this.errorMessageTarget.textContent = ""
      this.errorMessageTarget.classList.add("hidden")
    }
  }
  
  handleBackdropClick(event) {
    // Close modal if clicking on the backdrop (not the modal content)
    if (event.target === this.modalTarget) {
      this.close()
    }
  }
}