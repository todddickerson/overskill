import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["previewFrame"]
  static values = { 
    appId: String,
    currentVersion: String
  }

  connect() {
    // Listen for messages from chat iframes
    window.addEventListener('message', this.handleMessage.bind(this))
  }

  disconnect() {
    window.removeEventListener('message', this.handleMessage.bind(this))
  }

  handleMessage(event) {
    // Only handle messages from our domain
    if (event.origin !== window.location.origin) return

    const { action, version } = event.data

    switch (action) {
      case 'preview':
        this.previewVersion(version)
        break
      case 'compare':
        this.compareVersion(version)
        break
    }
  }

  async previewVersion(versionId) {
    try {
      // Update the preview frame to show this version
      const response = await fetch(`/account/apps/${this.appIdValue}/versions/${versionId}/preview`, {
        headers: {
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
        }
      })

      if (response.ok) {
        const previewUrl = `/account/apps/${this.appIdValue}/versions/${versionId}/preview`
        if (this.previewFrameTarget) {
          this.previewFrameTarget.src = previewUrl
        }
        
        // Show success notification
        this.showNotification(`Switched to version ${versionId}`, 'success')
      } else {
        this.showNotification('Failed to load version preview', 'error')
      }
    } catch (error) {
      console.error('Error previewing version:', error)
      this.showNotification('Error loading version preview', 'error')
    }
  }

  async compareVersion(versionId) {
    try {
      // Open version comparison in a modal or new tab
      const compareUrl = `/account/apps/${this.appIdValue}/versions/${versionId}/compare`
      
      // For now, we'll switch to the Code tab and highlight changes
      // In the future, this could open a diff view
      this.switchToCodeTab()
      this.showNotification(`Comparing with version ${versionId}`, 'info')
      
      // TODO: Implement proper diff view
      console.log('Compare version:', versionId)
    } catch (error) {
      console.error('Error comparing version:', error)
      this.showNotification('Error comparing versions', 'error')
    }
  }

  switchToCodeTab() {
    // Find and click the Code tab
    const codeTab = document.querySelector('[data-panel="code"]')
    if (codeTab) {
      codeTab.click()
    }
  }

  showNotification(message, type = 'info') {
    // Create a simple notification
    const notification = document.createElement('div')
    notification.className = `fixed top-4 right-4 z-50 px-4 py-2 rounded-lg text-white text-sm max-w-sm ${
      type === 'success' ? 'bg-green-600' : 
      type === 'error' ? 'bg-red-600' : 
      'bg-blue-600'
    }`
    notification.textContent = message

    document.body.appendChild(notification)

    // Remove after 3 seconds
    setTimeout(() => {
      notification.remove()
    }, 3000)
  }

  // Method to revert to current version
  revertToCurrent() {
    if (this.previewFrameTarget) {
      this.previewFrameTarget.src = `/account/apps/${this.appIdValue}/preview`
    }
    this.showNotification('Reverted to current version', 'info')
  }
}