import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["trigger"]
  
  connect() {
    // Find the parent chat container and scroll it
    const chatContainer = document.getElementById('chat_container')
    if (chatContainer) {
      chatContainer.scrollTop = chatContainer.scrollHeight
    }
    
    // If this is a trigger element, remove it after scrolling
    if (this.element.hasAttribute('data-chat-scroller-target')) {
      this.element.remove()
    }
  }

  scrollToBottom() {
    const container = this.element
    container.scrollTop = container.scrollHeight
  }
}