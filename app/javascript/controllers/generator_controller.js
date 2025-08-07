import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["prompt"]
  static values = { userSignedIn: Boolean }
  
  connect() {
    // If user is not signed in, we'll intercept form submission
    if (!this.userSignedInValue) {
      this.element.addEventListener('turbo:submit-start', this.handleSubmit.bind(this))
    }
  }
  
  handleSubmit(event) {
    // Store the prompt value before submission
    const prompt = this.promptTarget.value
    if (prompt) {
      // The controller will handle storing in cookies
      console.log("Submitting prompt for unauthenticated user:", prompt)
    }
  }
  
  fillPrompt(event) {
    // Called from template buttons
    const prompt = event.currentTarget.dataset.prompt
    const textarea = document.getElementById('custom-prompt')
    
    if (prompt && textarea) {
      textarea.value = prompt
      textarea.scrollIntoView({ behavior: 'smooth', block: 'center' })
      textarea.focus()
      textarea.dispatchEvent(new Event('input', { bubbles: true }))
    }
  }
}