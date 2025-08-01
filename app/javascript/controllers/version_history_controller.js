import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal", "content"]
  static values = { appId: String }

  open() {
    // Fetch latest version history
    this.fetchVersionHistory()
    
    // Show modal
    this.modalTarget.classList.remove('hidden')
    document.body.classList.add('overflow-hidden')
  }

  close() {
    this.modalTarget.classList.add('hidden')
    document.body.classList.remove('overflow-hidden')
  }

  fetchVersionHistory() {
    fetch(`/account/apps/${this.appIdValue}/versions`, {
      headers: {
        'Accept': 'text/html',
        'X-Requested-With': 'XMLHttpRequest'
      }
    })
    .then(response => response.text())
    .then(html => {
      this.contentTarget.innerHTML = html
    })
    .catch(error => {
      console.error('Error fetching version history:', error)
    })
  }

  // Handle ESC key
  keydown(event) {
    if (event.key === 'Escape') {
      this.close()
    }
  }

  connect() {
    // Add ESC key listener
    this.escapeHandler = this.keydown.bind(this)
    document.addEventListener('keydown', this.escapeHandler)
  }

  disconnect() {
    // Remove ESC key listener
    document.removeEventListener('keydown', this.escapeHandler)
  }
}