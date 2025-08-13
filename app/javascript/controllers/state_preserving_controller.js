import { Controller } from "@hotwired/stimulus"

// Preserves UI state (like details open/closed) across Action Cable updates
export default class extends Controller {
  static targets = ["container", "details"]

  connect() {
    this.restoreDetailsState()
    
    // Use MutationObserver to watch for DOM updates (Action Cable replacements)
    this.observer = new MutationObserver((mutations) => {
      mutations.forEach(mutation => {
        if (mutation.type === 'childList' && mutation.target === this.containerTarget) {
          // Container content was replaced, restore state after a short delay
          setTimeout(() => this.restoreDetailsState(), 10)
        }
      })
    })
    
    // Start observing the container for changes
    this.observer.observe(document.body, {
      childList: true,
      subtree: true,
      attributes: false
    })
  }

  disconnect() {
    if (this.observer) {
      this.observer.disconnect()
    }
  }

  // Save state before any potential update (called automatically)
  saveDetailsState() {
    const state = {}
    
    // Save details elements open state
    this.detailsTargets.forEach(details => {
      const detailsId = details.dataset.detailsId
      if (detailsId) {
        state[detailsId] = details.open
      }
    })
    
    // Store in sessionStorage with unique key
    const containerId = this.containerTarget.id
    if (containerId && Object.keys(state).length > 0) {
      sessionStorage.setItem(`state_${containerId}`, JSON.stringify(state))
    }
    
    return state
  }

  // Restore state after update
  restoreDetailsState() {
    const containerId = this.containerTarget.id
    if (!containerId) return

    const savedStateJson = sessionStorage.getItem(`state_${containerId}`)
    if (!savedStateJson) return

    try {
      const savedState = JSON.parse(savedStateJson)
      
      // Find current details elements and restore their state
      const currentDetailsElements = this.containerTarget.querySelectorAll('details[data-details-id]')
      currentDetailsElements.forEach(details => {
        const detailsId = details.dataset.detailsId
        if (detailsId && savedState.hasOwnProperty(detailsId)) {
          details.open = savedState[detailsId]
        }
      })
      
    } catch (error) {
      console.warn("Failed to restore details state:", error)
      sessionStorage.removeItem(`state_${containerId}`)
    }
  }

  // Event handler for details toggle - save state when user interacts
  detailsToggled(event) {
    this.saveDetailsState()
  }

  // Manual method to clear saved state
  clearState() {
    const containerId = this.containerTarget.id
    if (containerId) {
      sessionStorage.removeItem(`state_${containerId}`)
    }
  }
}