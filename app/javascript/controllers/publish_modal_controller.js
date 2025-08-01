import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content", "previewUrl", "productionUrl", "visitorCount", "updateButton"]
  static values = { appId: String }
  
  connect() {
    // Load current URLs and visitor count
    this.loadAppData()
  }
  
  open() {
    this.element.classList.remove("hidden")
    document.body.style.overflow = "hidden"
  }
  
  close(event) {
    if (event) event.preventDefault()
    this.element.classList.add("hidden")
    document.body.style.overflow = ""
  }
  
  // Close modal when clicking outside
  closeOnBackdrop(event) {
    if (event.target === this.element) {
      this.close()
    }
  }
  
  async loadAppData() {
    try {
      const response = await fetch(`/account/apps/${this.appIdValue}/deployment_info.json`)
      if (response.ok) {
        const data = await response.json()
        this.updateUrls(data)
        this.updateVisitorCount(data.visitor_count || 0)
      }
    } catch (error) {
      console.error("Failed to load app data:", error)
    }
  }
  
  updateUrls(data) {
    if (this.hasPreviewUrlTarget && data.preview_url) {
      const url = new URL(data.preview_url)
      this.previewUrlTarget.textContent = url.hostname
    }
    
    if (this.hasProductionUrlTarget && data.production_url) {
      const url = new URL(data.production_url)
      this.productionUrlTarget.textContent = url.hostname
    }
  }
  
  updateVisitorCount(count) {
    if (this.hasVisitorCountTarget) {
      this.visitorCountTarget.textContent = count
    }
  }
  
  async update(event) {
    event.preventDefault()
    
    // Show loading state
    const originalText = this.updateButtonTarget.textContent
    this.updateButtonTarget.textContent = "Updating..."
    this.updateButtonTarget.disabled = true
    
    try {
      // Trigger deployment
      const response = await fetch(`/account/apps/${this.appIdValue}/editor/deploy`, {
        method: 'POST',
        headers: {
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ environment: 'production' })
      })
      
      if (response.ok) {
        // Show success
        this.updateButtonTarget.textContent = "Updated!"
        this.updateButtonTarget.classList.remove("bg-blue-600", "hover:bg-blue-700")
        this.updateButtonTarget.classList.add("bg-green-600")
        
        // Reload app data after deployment
        setTimeout(() => {
          this.loadAppData()
          this.updateButtonTarget.textContent = originalText
          this.updateButtonTarget.classList.remove("bg-green-600")
          this.updateButtonTarget.classList.add("bg-blue-600", "hover:bg-blue-700")
          this.updateButtonTarget.disabled = false
        }, 2000)
      } else {
        throw new Error("Deployment failed")
      }
    } catch (error) {
      console.error("Update failed:", error)
      this.updateButtonTarget.textContent = "Update Failed"
      this.updateButtonTarget.classList.remove("bg-blue-600", "hover:bg-blue-700")
      this.updateButtonTarget.classList.add("bg-red-600")
      
      setTimeout(() => {
        this.updateButtonTarget.textContent = originalText
        this.updateButtonTarget.classList.remove("bg-red-600")
        this.updateButtonTarget.classList.add("bg-blue-600", "hover:bg-blue-700")
        this.updateButtonTarget.disabled = false
      }, 3000)
    }
  }
  
  async copyPreviewUrl(event) {
    event.preventDefault()
    const url = `https://${this.previewUrlTarget.textContent}`
    await this.copyToClipboard(url, event.currentTarget)
  }
  
  async copyProductionUrl(event) {
    event.preventDefault()
    const url = `https://${this.productionUrlTarget.textContent}`
    await this.copyToClipboard(url, event.currentTarget)
  }
  
  async copyToClipboard(text, button) {
    try {
      await navigator.clipboard.writeText(text)
      
      // Show success feedback
      const originalHtml = button.innerHTML
      button.innerHTML = '<svg class="w-5 h-5 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path></svg>'
      
      setTimeout(() => {
        button.innerHTML = originalHtml
      }, 2000)
    } catch (error) {
      console.error("Failed to copy:", error)
    }
  }
  
  openInNewTab(event) {
    event.preventDefault()
    const url = `https://${this.productionUrlTarget.textContent}`
    window.open(url, '_blank')
  }
}