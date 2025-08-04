import { Controller } from "@hotwired/stimulus"

// Controller to manage the editor layout including chat panel and activity monitor
export default class extends Controller {
  static targets = ["chatPanel", "collapseIcon", "activityModal"]
  static values = { chatVisible: Boolean }
  
  connect() {
    // Set initial state
    this.chatVisibleValue = true
  }
  
  // Toggle chat panel visibility
  toggleChat() {
    this.chatVisibleValue = !this.chatVisibleValue
    
    if (this.chatVisibleValue) {
      this.chatPanelTarget.style.width = '384px'
      this.collapseIconTarget.classList.remove('fa-chevron-right')
      this.collapseIconTarget.classList.add('fa-chevron-left')
    } else {
      this.chatPanelTarget.style.width = '0px'
      this.collapseIconTarget.classList.remove('fa-chevron-left')
      this.collapseIconTarget.classList.add('fa-chevron-right')
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
}