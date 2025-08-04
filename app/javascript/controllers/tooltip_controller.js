import { Controller } from "@hotwired/stimulus"

// Enhanced tooltip controller with better styling and positioning
export default class extends Controller {
  static targets = ["tooltip"]
  static values = { content: String, position: { type: String, default: "bottom" } }
  
  connect() {
    this.createTooltip()
  }
  
  disconnect() {
    // Clear any pending timeout
    if (this.showTimeout) {
      clearTimeout(this.showTimeout)
      this.showTimeout = null
    }
    this.removeTooltip()
  }
  
  show() {
    // Clear any existing timeout
    if (this.showTimeout) {
      clearTimeout(this.showTimeout)
    }
    
    // Show tooltip after 1 second delay
    this.showTimeout = setTimeout(() => {
      if (this.tooltip) {
        this.tooltip.classList.remove('opacity-0', 'pointer-events-none')
        this.tooltip.classList.add('opacity-100')
      }
    }, 1000)
  }
  
  hide() {
    // Clear show timeout if mouse leaves before tooltip shows
    if (this.showTimeout) {
      clearTimeout(this.showTimeout)
      this.showTimeout = null
    }
    
    if (this.tooltip) {
      this.tooltip.classList.remove('opacity-100')
      this.tooltip.classList.add('opacity-0', 'pointer-events-none')
    }
  }
  
  createTooltip() {
    if (!this.contentValue) return
    
    this.tooltip = document.createElement('div')
    this.tooltip.className = `absolute z-50 px-3 py-2 text-sm font-medium text-white bg-gray-900 dark:bg-gray-700 rounded-lg shadow-lg opacity-0 pointer-events-none transition-opacity duration-200 whitespace-nowrap`
    this.tooltip.textContent = this.contentValue
    
    // Position the tooltip
    this.positionTooltip()
    
    // Add to DOM
    this.element.appendChild(this.tooltip)
  }
  
  positionTooltip() {
    if (!this.tooltip) return
    
    switch(this.positionValue) {
      case 'top':
        this.tooltip.classList.add('bottom-full', 'left-1/2', 'transform', '-translate-x-1/2', 'mb-2')
        break
      case 'right':
        this.tooltip.classList.add('left-full', 'top-1/2', 'transform', '-translate-y-1/2', 'ml-2')
        break
      case 'left':
        this.tooltip.classList.add('right-full', 'top-1/2', 'transform', '-translate-y-1/2', 'mr-2')
        break
      default: // bottom
        this.tooltip.classList.add('top-full', 'left-1/2', 'transform', '-translate-x-1/2', 'mt-2')
    }
  }
  
  removeTooltip() {
    if (this.tooltip) {
      this.tooltip.remove()
      this.tooltip = null
    }
  }
}