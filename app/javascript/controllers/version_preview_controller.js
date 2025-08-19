import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["iframe", "versionHeader", "restoreButton", "currentVersionBadge"]
  
  connect() {
    // Listen for postMessage from chat iframe
    window.addEventListener("message", this.handleMessage.bind(this))
    
    // Store the current app ID for version restoration
    this.appId = this.data.get("appId")
    this.currentVersionId = null
    
    // Listen for preview updates via ActionCable
    this.setupPreviewUpdateListener()
  }
  
  disconnect() {
    window.removeEventListener("message", this.handleMessage.bind(this))
  }
  
  handleMessage(event) {
    // Verify the message is from our chat iframe
    if (!event.data || typeof event.data !== 'object') return
    
    const { action, version } = event.data
    
    if (action === 'preview' && version) {
      this.previewVersion(version)
    } else if (action === 'compare' && version) {
      // This could open the compare modal or switch to compare view
      this.compareVersion(version)
    } else if (action === 'restore' && version) {
      this.restoreSpecificVersion(version)
    }
  }
  
  async previewVersion(versionId) {
    // Update the iframe to show the specific version
    const versionPreviewUrl = `/account/app_versions/${versionId}/preview`
    this.iframeTarget.src = versionPreviewUrl
    
    // Store the current version ID
    this.currentVersionId = versionId
    
    // Show version header
    this.versionHeaderTarget.classList.remove("hidden")
    
    // Fetch version details to update the header
    try {
      const response = await fetch(`/account/app_versions/${versionId}.json`)
      const version = await response.json()
      
      // Update version badge
      this.currentVersionBadgeTarget.textContent = `v${version.version_number}`
      
      // Show restore button if not the latest version
      if (!version.is_latest) {
        this.restoreButtonTarget.classList.remove("hidden")
      } else {
        this.restoreButtonTarget.classList.add("hidden")
      }
    } catch (error) {
      console.error("Failed to fetch version details:", error)
    }
  }
  
  async restoreVersion() {
    if (!this.currentVersionId) return
    
    // Confirm restoration
    if (!confirm("Restore this version? This will create a new version with the contents of this version.")) {
      return
    }
    
    try {
      const response = await fetch(`/account/app_versions/${this.currentVersionId}/restore`, {
        method: 'POST',
        headers: {
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
          'Content-Type': 'application/json'
        }
      })
      
      if (response.ok) {
        const result = await response.json()
        
        // Refresh the page to show the new version
        window.location.reload()
      } else {
        alert("Failed to restore version. Please try again.")
      }
    } catch (error) {
      console.error("Failed to restore version:", error)
      alert("An error occurred while restoring the version.")
    }
  }
  
  async restoreSpecificVersion(event) {
    const versionId = event.currentTarget.dataset.versionId
    if (!versionId) {
      console.error("No version ID found for restore")
      return
    }
    
    try {
      const response = await fetch(`/account/app_versions/${versionId}/restore`, {
        method: 'POST',
        headers: {
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
          'Content-Type': 'application/json'
        }
      })
      
      if (response.ok) {
        const result = await response.json()
        
        // Refresh the page to show the new version
        window.location.reload()
      } else {
        alert("Failed to restore version. Please try again.")
      }
    } catch (error) {
      console.error("Failed to restore version:", error)
      alert("An error occurred while restoring the version.")
    }
  }
  
  showLatest() {
    // Return to the latest version preview
    const latestPreviewUrl = `/account/apps/${this.appId}/preview`
    this.iframeTarget.src = latestPreviewUrl
    
    // Hide version header
    this.versionHeaderTarget.classList.add("hidden")
    this.currentVersionId = null
  }
  
  compareVersion(versionId) {
    // This could be expanded to show a diff view
    // For now, just switch to the Code tab with version comparison
    const codeTab = document.querySelector('[data-tabs-target="button"][data-panel="code"]')
    if (codeTab) {
      codeTab.click()
      
      // Dispatch event for code editor to show version diff
      window.dispatchEvent(new CustomEvent('show-version-diff', { 
        detail: { versionId } 
      }))
    }
  }
  
  setupPreviewUpdateListener() {
    // Listen for preview updates via custom events
    window.addEventListener('preview-updated', this.handlePreviewUpdate.bind(this))
    
    // Also listen for the Turbo stream replacement to detect when preview frame updates
    document.addEventListener('turbo:before-stream-render', (event) => {
      if (event.target && event.target.id === 'preview_frame') {
        // Preview frame is being replaced, refresh the iframe after a short delay
        setTimeout(() => this.refreshPreview(), 100)
      }
    })
  }
  
  handlePreviewUpdate(event) {
    if (event.detail && event.detail.appId === this.appId) {
      this.refreshPreview(event.detail.previewUrl)
    }
  }
  
  refreshPreview(newUrl = null) {
    // Only refresh if we're showing the latest version (not a historical one)
    if (this.currentVersionId) return
    
    if (newUrl) {
      // Use the provided URL
      this.iframeTarget.src = newUrl + '?t=' + Date.now()
    } else {
      // Force reload the current iframe by adding a timestamp
      const currentSrc = this.iframeTarget.src
      const separator = currentSrc.includes('?') ? '&' : '?'
      this.iframeTarget.src = currentSrc.split('?')[0] + separator + 't=' + Date.now()
    }
  }
}