import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content", "toggle", "showMore", "showLess"]
  static values = { collapsedHeight: Number }
  
  connect() {
    this.checkHeight()
  }
  
  checkHeight() {
    const contentHeight = this.contentTarget.scrollHeight
    const collapsedHeight = this.collapsedHeightValue || 100
    
    if (contentHeight > collapsedHeight) {
      this.contentTarget.style.maxHeight = `${collapsedHeight}px`
      this.contentTarget.style.overflow = "hidden"
      this.contentTarget.classList.add("relative")
      
      // Add gradient fade
      const gradient = document.createElement("div")
      const bgColor = this.element.closest('.bg-gray-700') ? 'from-gray-700' : 'from-gray-750'
      gradient.className = `absolute bottom-0 left-0 right-0 h-8 bg-gradient-to-t ${bgColor} to-transparent pointer-events-none`
      gradient.dataset.expandableTextTarget = "gradient"
      this.contentTarget.appendChild(gradient)
      
      this.toggleTarget.classList.remove("hidden")
    }
  }
  
  toggle() {
    const isExpanded = this.contentTarget.style.maxHeight === "none"
    
    if (isExpanded) {
      // Collapse
      this.contentTarget.style.maxHeight = `${this.collapsedHeightValue}px`
      this.showMoreTarget.classList.remove("hidden")
      this.showLessTarget.classList.add("hidden")
      
      // Show gradient
      const gradient = this.contentTarget.querySelector('[data-expandable-text-target="gradient"]')
      if (gradient) gradient.classList.remove("hidden")
    } else {
      // Expand
      this.contentTarget.style.maxHeight = "none"
      this.showMoreTarget.classList.add("hidden")
      this.showLessTarget.classList.remove("hidden")
      
      // Hide gradient
      const gradient = this.contentTarget.querySelector('[data-expandable-text-target="gradient"]')
      if (gradient) gradient.classList.add("hidden")
    }
  }
}