import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["prompt"]
  static values = { userSignedIn: Boolean }
  
  connect() {
    this.restorePrompt()
    this.bindPersistence()
    this.focusPrimaryCtaIfReturning()
    
    // If user is not signed in, remember prompt on submit so we can resume post-login
    if (!this.userSignedInValue) this.element.addEventListener('turbo:submit-start', this.rememberPrompt)
  }
  
  // Persist prompt locally while typing (no network)
  bindPersistence() {
    if (!this.hasPromptTarget) return
    this.promptTarget.addEventListener('input', () => {
      localStorage.setItem('overskill:pending_prompt', this.promptTarget.value)
    })
  }

  restorePrompt() {
    if (!this.hasPromptTarget) return
    const saved = localStorage.getItem('overskill:pending_prompt')
    if (saved && !this.promptTarget.value) this.promptTarget.value = saved
  }

  rememberPrompt = () => {
    if (!this.hasPromptTarget) return
    localStorage.setItem('overskill:pending_prompt', this.promptTarget.value)
  }

  focusPrimaryCtaIfReturning() {
    // If user just logged in (body data attribute), highlight prompt and focus the CTA button
    const signedIn = document.body.dataset.userSignedIn === 'true'
    if (signedIn) {
      const btn = document.getElementById('generate-btn')
      const prompt = this.promptTarget
      if (prompt) {
        prompt.classList.add('ring-2', 'ring-primary-500', 'ring-offset-2')
        setTimeout(() => prompt.classList.remove('ring-2', 'ring-primary-500', 'ring-offset-2'), 1200)
      }
      if (btn) btn.focus()
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