import { Controller } from "@hotwired/stimulus"

// Controller to make panels resizable by dragging
export default class extends Controller {
  static targets = ["handle"]
  static values = { 
    minWidth: Number,
    maxWidth: Number,
    defaultWidth: Number
  }
  
  connect() {
    this.isResizing = false
    this.startX = 0
    this.startWidth = 0
    
    // Set initial width if not already set
    if (!this.element.style.width) {
      this.element.style.width = `${this.defaultWidthValue}px`
    }
    
    // Add event listeners
    this.handleTarget.addEventListener('mousedown', this.startResize.bind(this))
    document.addEventListener('mousemove', this.resize.bind(this))
    document.addEventListener('mouseup', this.stopResize.bind(this))
  }
  
  disconnect() {
    // Clean up event listeners
    document.removeEventListener('mousemove', this.resize.bind(this))
    document.removeEventListener('mouseup', this.stopResize.bind(this))
  }
  
  startResize(event) {
    this.isResizing = true
    this.startX = event.clientX
    this.startWidth = this.element.offsetWidth
    
    // Prevent text selection while resizing
    document.body.style.userSelect = 'none'
    document.body.style.cursor = 'col-resize'
    
    // Add visual feedback
    this.handleTarget.style.backgroundColor = 'rgb(59, 130, 246)'
    this.handleTarget.style.opacity = '0.3'
  }
  
  resize(event) {
    if (!this.isResizing) return
    
    const currentX = event.clientX
    const deltaX = currentX - this.startX
    let newWidth = this.startWidth + deltaX
    
    // Enforce min/max constraints
    newWidth = Math.max(this.minWidthValue, Math.min(this.maxWidthValue, newWidth))
    
    // Apply the new width
    this.element.style.width = `${newWidth}px`
    this.element.style.minWidth = `${newWidth}px`
  }
  
  stopResize() {
    if (!this.isResizing) return
    
    this.isResizing = false
    
    // Reset cursor and selection
    document.body.style.userSelect = ''
    document.body.style.cursor = ''
    
    // Reset handle appearance
    this.handleTarget.style.backgroundColor = ''
    this.handleTarget.style.opacity = ''
    
    // Save the width to localStorage for persistence
    const currentWidth = this.element.offsetWidth
    localStorage.setItem('chatPanelWidth', currentWidth)
  }
  
  initialize() {
    // Restore saved width from localStorage
    const savedWidth = localStorage.getItem('chatPanelWidth')
    if (savedWidth) {
      const width = parseInt(savedWidth)
      if (width >= this.minWidthValue && width <= this.maxWidthValue) {
        this.element.style.width = `${width}px`
        this.element.style.minWidth = `${width}px`
      }
    }
  }
}