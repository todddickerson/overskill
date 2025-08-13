import { Controller } from "@hotwired/stimulus"

// Preserves UI state (like details open/closed, scroll position) across Action Cable updates
export default class extends Controller {
  static targets = ["container", "details", "toggleText"]

  connect() {
    this.restoreDetailsState()
    this.restoreScrollState()
    this.updateToggleTexts()
    
    // Use MutationObserver to watch for DOM updates (Action Cable replacements)
    this.observer = new MutationObserver((mutations) => {
      mutations.forEach(mutation => {
        if (mutation.type === 'childList' && mutation.target === this.containerTarget) {
          // Container content was replaced, restore state after a short delay
          setTimeout(() => {
            this.restoreDetailsState()
            this.restoreScrollState()
            this.updateToggleTexts()
          }, 10)
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

  // Save scroll state for chat container
  saveScrollState() {
    const chatContainer = document.getElementById('chat_container')
    if (!chatContainer) return

    const containerId = this.containerTarget.id
    if (!containerId) return

    // Check if user was scrolled near the bottom (within 100px)
    const scrollTop = chatContainer.scrollTop
    const scrollHeight = chatContainer.scrollHeight
    const clientHeight = chatContainer.clientHeight
    const isNearBottom = (scrollTop + clientHeight) >= (scrollHeight - 100)

    const scrollState = {
      wasNearBottom: isNearBottom,
      scrollTop: scrollTop
    }

    sessionStorage.setItem(`scroll_${containerId}`, JSON.stringify(scrollState))
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

  // Restore scroll state for chat container
  restoreScrollState() {
    const chatContainer = document.getElementById('chat_container')
    if (!chatContainer) return

    const containerId = this.containerTarget.id
    if (!containerId) return

    const savedScrollJson = sessionStorage.getItem(`scroll_${containerId}`)
    if (!savedScrollJson) return

    try {
      const scrollState = JSON.parse(savedScrollJson)
      
      // If user was near bottom, scroll to bottom after content update
      if (scrollState.wasNearBottom) {
        // Use setTimeout to ensure DOM has updated
        setTimeout(() => {
          chatContainer.scrollTop = chatContainer.scrollHeight
        }, 20)
      } else {
        // Restore previous scroll position
        chatContainer.scrollTop = scrollState.scrollTop
      }
      
    } catch (error) {
      console.warn("Failed to restore scroll state:", error)
      sessionStorage.removeItem(`scroll_${containerId}`)
    }
  }

  // Update toggle text based on details state
  updateToggleTexts() {
    // Find all details elements and their associated toggle text
    const currentDetailsElements = this.containerTarget.querySelectorAll('details[data-details-id]')
    const toggleTextElements = this.containerTarget.querySelectorAll('[data-state-preserving-target="toggleText"]')
    
    currentDetailsElements.forEach(details => {
      const detailsId = details.dataset.detailsId
      
      // Find corresponding toggle text element
      const toggleText = Array.from(toggleTextElements).find(el => {
        // Look for toggle text within the same details element
        return details.contains(el)
      })
      
      if (toggleText) {
        const showText = toggleText.dataset.showText || "Show All"
        const hideText = toggleText.dataset.hideText || "Hide"
        
        // Update text based on details open state
        toggleText.textContent = details.open ? hideText : showText
      }
    })
  }

  // Event handler for details toggle - save state when user interacts
  detailsToggled(event) {
    this.saveDetailsState()
    this.saveScrollState()
    
    // Update toggle text immediately on user interaction
    setTimeout(() => this.updateToggleTexts(), 1)
  }

  // Manual method to clear saved state
  clearState() {
    const containerId = this.containerTarget.id
    if (containerId) {
      sessionStorage.removeItem(`state_${containerId}`)
    }
  }
}