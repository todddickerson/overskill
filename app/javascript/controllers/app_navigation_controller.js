import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dropdown", "trigger"]
  
  connect() {
    // Close dropdown when clicking outside
    document.addEventListener("click", this.closeOnClickOutside.bind(this))
  }
  
  disconnect() {
    document.removeEventListener("click", this.closeOnClickOutside.bind(this))
  }
  
  toggle(event) {
    event.preventDefault()
    event.stopPropagation()
    
    if (this.dropdownTarget.classList.contains("hidden")) {
      this.open()
    } else {
      this.close()
    }
  }
  
  open() {
    this.dropdownTarget.classList.remove("hidden")
    this.triggerTarget.classList.add("bg-gray-700")
    
    // Add backdrop blur effect
    document.body.style.backdropFilter = "blur(2px)"
  }
  
  close() {
    this.dropdownTarget.classList.add("hidden")
    this.triggerTarget.classList.remove("bg-gray-700")
    
    // Remove backdrop blur effect
    document.body.style.backdropFilter = ""
  }
  
  closeOnClickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.close()
    }
  }
  
  openSettings(event) {
    event.preventDefault()
    // TODO: Open app settings modal
    console.log("Opening app settings...")
    this.close()
  }
  
  renameProject(event) {
    event.preventDefault()
    // TODO: Open rename project modal
    console.log("Opening rename project...")
    this.close()
  }
  
  manageCredits(event) {
    event.preventDefault()
    // TODO: Open credits management
    console.log("Opening credits management...")
    this.close()
  }
  
  getHelp(event) {
    event.preventDefault()
    // TODO: Open help/support
    console.log("Opening help...")
    this.close()
  }
}