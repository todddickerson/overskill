import { Controller } from "@hotwired/stimulus"
import { post } from "@rails/request.js"

export default class extends Controller {
  static targets = ["modal", "loginForm", "signupForm", "loginTab", "signupTab", "errorMessage"]
  static values = { 
    returnUrl: String,
    prompt: String 
  }
  
  connect() {
    // Hide modal on initial load
    this.element.classList.add("hidden")
  }
  
  open(event) {
    if (event.detail) {
      // Store the prompt and any other data we need after auth
      this.promptValue = event.detail.prompt || ""
      this.returnUrlValue = event.detail.returnUrl || ""
    }
    
    this.element.classList.remove("hidden")
    document.body.style.overflow = "hidden" // Prevent background scrolling
  }
  
  close() {
    this.element.classList.add("hidden")
    document.body.style.overflow = "" // Re-enable scrolling
    this.clearErrors()
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
  
  async submitLogin(event) {
    event.preventDefault()
    const form = event.target
    const formData = new FormData(form)
    
    // Add the stored prompt to continue after login
    if (this.promptValue) {
      formData.append("prompt", this.promptValue)
    }
    
    try {
      const response = await post(form.action, {
        body: formData,
        responseKind: "json"
      })
      
      if (response.ok) {
        const data = await response.json
        if (data.success) {
          // If we have a redirect URL, go there
          if (data.redirect_url) {
            window.location.href = data.redirect_url
          } else if (this.returnUrlValue) {
            window.location.href = this.returnUrlValue
          } else {
            // Reload to continue with the generator flow
            window.location.reload()
          }
        } else {
          this.showError(data.error || "Invalid email or password")
        }
      } else {
        this.showError("An error occurred. Please try again.")
      }
    } catch (error) {
      console.error("Login error:", error)
      this.showError("An error occurred. Please try again.")
    }
  }
  
  async submitSignup(event) {
    event.preventDefault()
    const form = event.target
    const formData = new FormData(form)
    
    // Add the stored prompt to continue after signup
    if (this.promptValue) {
      formData.append("prompt", this.promptValue)
    }
    
    try {
      const response = await post(form.action, {
        body: formData,
        responseKind: "json"
      })
      
      if (response.ok) {
        const data = await response.json
        if (data.success) {
          // If we have a redirect URL, go there
          if (data.redirect_url) {
            window.location.href = data.redirect_url
          } else if (this.returnUrlValue) {
            window.location.href = this.returnUrlValue
          } else {
            // Reload to continue with the generator flow
            window.location.reload()
          }
        } else {
          this.showError(data.error || "Please check the form and try again")
        }
      } else {
        this.showError("An error occurred. Please try again.")
      }
    } catch (error) {
      console.error("Signup error:", error)
      this.showError("An error occurred. Please try again.")
    }
  }
  
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