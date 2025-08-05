import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal", "previewUrl", "productionUrl", "editorUrl"]
  static values = { appId: String }
  
  open() {
    console.log('ShareModalController.open() called')
    if (this.hasModalTarget) {
      this.modalTarget.classList.remove("hidden")
      document.body.style.overflow = "hidden"
    }
  }
  
  close(event) {
    if (event) event.preventDefault()
    if (this.hasModalTarget) {
      this.modalTarget.classList.add("hidden")
      document.body.style.overflow = ""
    }
  }
  
  // Close modal when clicking outside
  closeOnBackdrop(event) {
    if (event.target === this.modalTarget) {
      this.close()
    }
  }
  
  async copyPreviewUrl(event) {
    event.preventDefault()
    if (this.hasPreviewUrlTarget) {
      await this.copyToClipboard(this.previewUrlTarget.value, event.currentTarget)
    }
  }
  
  async copyProductionUrl(event) {
    event.preventDefault()
    if (this.hasProductionUrlTarget) {
      await this.copyToClipboard(this.productionUrlTarget.value, event.currentTarget)
    }
  }
  
  async copyEditorUrl(event) {
    event.preventDefault()
    if (this.hasEditorUrlTarget) {
      await this.copyToClipboard(this.editorUrlTarget.value, event.currentTarget)
    }
  }
  
  async copyToClipboard(text, button) {
    try {
      await navigator.clipboard.writeText(text)
      
      // Show success feedback
      const originalHtml = button.innerHTML
      button.innerHTML = '<i class="fas fa-check text-green-600"></i>'
      
      setTimeout(() => {
        button.innerHTML = originalHtml
      }, 2000)
    } catch (error) {
      console.error("Failed to copy:", error)
    }
  }
  
  shareTwitter(event) {
    event.preventDefault()
    const url = this.hasProductionUrlTarget ? this.productionUrlTarget.value : this.previewUrlTarget.value
    const text = `Check out my app built with @overskill_ai: `
    const twitterUrl = `https://twitter.com/intent/tweet?text=${encodeURIComponent(text)}&url=${encodeURIComponent(url)}`
    window.open(twitterUrl, '_blank', 'width=550,height=420')
  }
  
  shareLinkedIn(event) {
    event.preventDefault()
    const url = this.hasProductionUrlTarget ? this.productionUrlTarget.value : this.previewUrlTarget.value
    const linkedInUrl = `https://www.linkedin.com/sharing/share-offsite/?url=${encodeURIComponent(url)}`
    window.open(linkedInUrl, '_blank', 'width=550,height=550')
  }
}