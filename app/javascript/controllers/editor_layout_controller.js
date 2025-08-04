import { Controller } from "@hotwired/stimulus"

// Controller to manage the editor layout including chat panel and activity monitor
export default class extends Controller {
  static targets = ["chatPanel", "collapseIcon", "activityModal", "expandButton", "floatingEditButton"]
  static values = { chatVisible: Boolean }
  
  connect() {
    // Set initial state
    this.chatVisibleValue = true
  }
  
  // Toggle chat panel visibility
  toggleChat() {
    this.chatVisibleValue = !this.chatVisibleValue
    
    // Check if we're on mobile (using Tailwind's lg breakpoint)
    const isMobile = window.innerWidth < 1024
    
    if (this.chatVisibleValue) {
      if (isMobile) {
        // On mobile, show chat panel (it's a bottom sheet)
        this.chatPanelTarget.style.display = 'flex'
        this.chatPanelTarget.classList.remove('hidden')
      } else {
        // Desktop behavior - restore previous width or default
        const savedWidth = localStorage.getItem('chatPanelWidth') || '384'
        this.chatPanelTarget.style.width = `${savedWidth}px`
        this.chatPanelTarget.style.minWidth = `${savedWidth}px`
        this.chatPanelTarget.style.display = 'flex'
        this.chatPanelTarget.classList.remove('hidden')
      }
      
      // Hide expand button when chat is visible
      if (this.hasExpandButtonTarget) {
        this.expandButtonTarget.classList.add('hidden')
      }
    } else {
      if (isMobile) {
        // On mobile, hide chat panel completely
        this.chatPanelTarget.style.display = 'none'
        this.chatPanelTarget.classList.add('hidden')
      } else {
        // Desktop behavior - collapse to 0 width
        const currentWidth = this.chatPanelTarget.offsetWidth
        if (currentWidth > 0) {
          localStorage.setItem('chatPanelWidth', currentWidth)
        }
        this.chatPanelTarget.style.width = '0px'
        this.chatPanelTarget.style.minWidth = '0px'
      }
      
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
  
  // Open mobile chat as full screen overlay
  openMobileChat() {
    // Show chat panel and make it full screen on mobile
    this.chatPanelTarget.classList.remove('hidden', 'h-1/2', 'order-2', 'lg:flex')
    this.chatPanelTarget.classList.add('flex', 'fixed', 'inset-0', 'z-50', 'h-full')
    
    // Hide floating button while chat is open
    if (this.hasFloatingEditButtonTarget) {
      this.floatingEditButtonTarget.classList.add('hidden')
    }
    
    // Update close button action for mobile
    const closeButton = this.chatPanelTarget.querySelector('[data-action*="editor-layout#toggleChat"]')
    if (closeButton) {
      closeButton.dataset.action = 'click->editor-layout#closeMobileChat'
    }
  }
  
  // Close mobile chat
  closeMobileChat() {
    // Hide chat panel on mobile
    this.chatPanelTarget.classList.remove('flex', 'fixed', 'inset-0', 'z-50', 'h-full')
    this.chatPanelTarget.classList.add('hidden', 'lg:flex', 'h-1/2', 'order-2')
    
    // Show floating button again
    if (this.hasFloatingEditButtonTarget) {
      this.floatingEditButtonTarget.classList.remove('hidden')
    }
    
    // Restore toggle action
    const closeButton = this.chatPanelTarget.querySelector('[data-action*="editor-layout#closeMobileChat"]')
    if (closeButton) {
      closeButton.dataset.action = 'click->editor-layout#toggleChat'
    }
  }
}