import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["iframe", "versionHeader", "restoreButton", "currentVersionBadge"]
  
  connect() {
    // Listen for postMessage from chat iframe
    window.addEventListener("message", this.handleMessage.bind(this))
    
    // Store the current app ID for version restoration
    this.appId = this.data.get("appId")
    this.currentVersionId = null
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
    }
  }
  
  async previewVersion(versionId) {
    // Update the iframe to show the specific version
    const versionPreviewUrl = `/account/apps/${this.appId}/versions/${versionId}/preview`
    this.iframeTarget.src = versionPreviewUrl
    
    // Store the current version ID
    this.currentVersionId = versionId
    
    // Show version header
    this.versionHeaderTarget.classList.remove("hidden")
    
    // Fetch version details to update the header
    try {
      const response = await fetch(`/account/apps/${this.appId}/versions/${versionId}.json`)
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
      const response = await fetch(`/account/apps/${this.appId}/versions/${this.currentVersionId}/restore`, {
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
}