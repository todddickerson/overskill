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
    const shareModal = document.querySelector('#share_modal')
    if (shareModal) {
      const controller = this.application.getControllerForElementAndIdentifier(shareModal, 'share-modal')
      if (controller && controller.open) {
        controller.open()
      } else {
        console.error('Share modal controller not found or no open method')
      }
    } else {
      console.error('Share modal element not found')
    }
  }
  
  // Open publish modal
  openPublishModal() {
    const publishModal = document.querySelector('#publish_modal')
    if (publishModal) {
      const controller = this.application.getControllerForElementAndIdentifier(publishModal, 'publish-modal')
      if (controller && controller.open) {
        controller.open()
      } else {
        console.error('Publish modal controller not found or no open method')
      }
    } else {
      console.error('Publish modal element not found')
    }
  }
  
  // Open invite modal  
  openInviteModal() {
    const inviteModal = document.querySelector('#invite_modal')
    if (inviteModal) {
      const controller = this.application.getControllerForElementAndIdentifier(inviteModal, 'invite-modal')
      if (controller && controller.open) {
        controller.open()
      } else {
        console.error('Invite modal controller not found or no open method')
      }
    } else {
      console.error('Invite modal element not found')
    }
  }
  
  // Open help modal
  openHelpModal() {
    const helpModal = document.querySelector('#help_modal')
    if (helpModal) {
      const controller = this.application.getControllerForElementAndIdentifier(helpModal, 'help-modal')
      if (controller && controller.open) {
        controller.open()
      } else {
        console.error('Help modal controller not found or no open method')
      }
    } else {
      console.error('Help modal element not found')
    }
  }
  
  // Deprecated mobile chat methods - now handled by mobile-navigation controller
  openMobileChat() {
    console.warn('openMobileChat is deprecated. Use mobile-navigation controller instead.')
  }
  
  closeMobileChat() {
    console.warn('closeMobileChat is deprecated. Use mobile-navigation controller instead.')
  }
}