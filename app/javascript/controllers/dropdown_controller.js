import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu"]
  
  connect() {
    // Close dropdown when clicking outside
    this.closeOnClickOutside = this.closeOnClickOutside.bind(this)
    
    // Listen for other dropdowns opening
    this.handleDropdownOpened = this.handleDropdownOpened.bind(this)
    window.addEventListener('dropdown:opened', this.handleDropdownOpened)
  }
  
  handleDropdownOpened(event) {
    // If another dropdown opened, close this one
    if (event.detail.controller !== this) {
      this.close()
    }
  }
  
  toggle(event) {
    event.preventDefault()
    event.stopPropagation()
    
    if (this.menuTarget.classList.contains("hidden")) {
      this.open()
    } else {
      this.close()
    }
  }
  
  open() {
    this.menuTarget.classList.remove("hidden")
    document.addEventListener("click", this.closeOnClickOutside)
    
    // Dispatch event to notify other dropdowns
    window.dispatchEvent(new CustomEvent('dropdown:opened', { detail: { controller: this } }))
  }
  
  close() {
    this.menuTarget.classList.add("hidden")
    document.removeEventListener("click", this.closeOnClickOutside)
  }
  
  closeOnClickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.close()
    }
  }
  
  disconnect() {
    document.removeEventListener("click", this.closeOnClickOutside)
    window.removeEventListener('dropdown:opened', this.handleDropdownOpened)
  }
}