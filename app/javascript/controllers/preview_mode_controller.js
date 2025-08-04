import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["preview", "modeButton", "statusText"]
  static values = { 
    mode: String,
    appId: String
  }
  
  connect() {
    this.mode = this.modeValue || 'auto'
    this.updateUI()
    
    // Listen for file changes to update preview
    document.addEventListener('file-saved', () => {
      if (this.mode === 'auto') {
        this.refreshPreview()
      }
    })
  }
  
  toggleMode() {
    // Cycle through modes: auto -> manual -> paused -> auto
    const modes = ['auto', 'manual', 'paused']
    const currentIndex = modes.indexOf(this.mode)
    this.mode = modes[(currentIndex + 1) % modes.length]
    
    this.updateUI()
    this.savePreference()
    
    if (this.mode === 'auto') {
      this.refreshPreview()
    }
  }
  
  refreshPreview() {
    if (this.mode === 'paused') return
    
    // Add loading state
    this.previewTarget.classList.add('opacity-50')
    
    // Reload iframe
    const iframe = this.previewTarget.querySelector('iframe')
    if (iframe) {
      iframe.src = iframe.src
      
      iframe.onload = () => {
        this.previewTarget.classList.remove('opacity-50')
        this.showNotification('Preview updated')
      }
    }
  }
  
  updateUI() {
    // Update button appearance
    const button = this.modeButtonTarget
    const statusText = this.statusTextTarget
    
    button.classList.remove('text-green-600', 'text-yellow-600', 'text-gray-600')
    button.classList.remove('bg-green-100', 'bg-yellow-100', 'bg-gray-100')
    button.classList.remove('dark:bg-green-900/50', 'dark:bg-yellow-900/50', 'dark:bg-gray-900/50')
    
    switch (this.mode) {
      case 'auto':
        button.classList.add('text-green-600', 'bg-green-100', 'dark:bg-green-900/50')
        statusText.textContent = 'Auto-refresh ON'
        button.innerHTML = '<i class="fas fa-sync mr-2"></i>Auto'
        break
      case 'manual':
        button.classList.add('text-yellow-600', 'bg-yellow-100', 'dark:bg-yellow-900/50')
        statusText.textContent = 'Manual refresh'
        button.innerHTML = '<i class="fas fa-hand-pointer mr-2"></i>Manual'
        break
      case 'paused':
        button.classList.add('text-gray-600', 'bg-gray-100', 'dark:bg-gray-900/50')
        statusText.textContent = 'Preview paused'
        button.innerHTML = '<i class="fas fa-pause mr-2"></i>Paused'
        break
    }
  }
  
  savePreference() {
    // Save user's preference
    localStorage.setItem(`preview_mode_${this.appIdValue}`, this.mode)
  }
  
  showNotification(message) {
    // Create a temporary notification
    const notification = document.createElement('div')
    notification.className = 'fixed bottom-4 right-4 bg-green-500 text-white px-4 py-2 rounded shadow-lg z-50'
    notification.textContent = message
    document.body.appendChild(notification)
    
    setTimeout(() => {
      notification.remove()
    }, 2000)
  }
}