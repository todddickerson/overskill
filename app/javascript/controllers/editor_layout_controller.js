import { Controller } from "@hotwired/stimulus"

// Controller to manage the editor layout including chat panel and activity monitor
export default class extends Controller {
  static targets = ["chatPanel", "collapseIcon", "activityModal", "expandButton"]
  static values = { chatVisible: Boolean }
  
  connect() {
    // Set initial state
    this.chatVisibleValue = true
  }
  
  // Toggle chat panel visibility
  toggleChat() {
    this.chatVisibleValue = !this.chatVisibleValue
    
    if (this.chatVisibleValue) {
      // Restore previous width or default
      const savedWidth = localStorage.getItem('chatPanelWidth') || '384'
      this.chatPanelTarget.style.width = `${savedWidth}px`
      this.chatPanelTarget.style.minWidth = `${savedWidth}px`
      
      // Hide expand button when chat is visible
      if (this.hasExpandButtonTarget) {
        this.expandButtonTarget.classList.add('hidden')
      }
    } else {
      // Save current width before hiding
      const currentWidth = this.chatPanelTarget.offsetWidth
      if (currentWidth > 0) {
        localStorage.setItem('chatPanelWidth', currentWidth)
      }
      this.chatPanelTarget.style.width = '0px'
      this.chatPanelTarget.style.minWidth = '0px'
      
      // Show expand button when chat is hidden
      if (this.hasExpandButtonTarget) {
        this.expandButtonTarget.classList.remove('hidden')
      }
    }
  }
  
  // Show activity monitor modal
  toggleActivityMonitor() {
    this.activityModalTarget.classList.toggle('hidden')
  }
  
  // Close activity monitor
  closeActivityMonitor() {
    this.activityModalTarget.classList.add('hidden')
  }
  
  // Open version history modal
  openVersionHistory() {
    const versionHistoryModal = document.querySelector('[data-version-history-target="modal"]')
    if (versionHistoryModal) {
      versionHistoryModal.classList.remove('hidden')
    }
  }
  
  // Open share modal
  openShareModal() {
    // Create and show share modal
    console.log('Share modal functionality to be implemented')
    // For now, just copy the current URL to clipboard
    const currentUrl = window.location.href
    navigator.clipboard.writeText(currentUrl).then(() => {
      // Show temporary notification
      const notification = document.createElement('div')
      notification.textContent = 'URL copied to clipboard!'
      notification.className = 'fixed top-4 right-4 bg-green-500 text-white px-4 py-2 rounded shadow-lg z-50'
      document.body.appendChild(notification)
      setTimeout(() => {
        document.body.removeChild(notification)
      }, 2000)
    })
  }
}