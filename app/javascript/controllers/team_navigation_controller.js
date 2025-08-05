import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dropdown", "trigger"]
  
  connect() {
    // Close dropdown when clicking outside
    document.addEventListener("click", this.closeOnClickOutside.bind(this))
    
    // Listen for other dropdowns opening
    this.handleDropdownOpened = this.handleDropdownOpened.bind(this)
    window.addEventListener('dropdown:opened', this.handleDropdownOpened)
  }
  
  disconnect() {
    document.removeEventListener("click", this.closeOnClickOutside.bind(this))
    window.removeEventListener('dropdown:opened', this.handleDropdownOpened)
  }
  
  handleDropdownOpened(event) {
    // If another dropdown opened, close this one
    if (event.detail.controller !== this) {
      this.close()
    }
  }
  
  closeOtherDropdowns() {
    // This will trigger the close on all other dropdowns via the event system
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
    // Close any other open dropdowns
    this.closeOtherDropdowns()
    
    this.dropdownTarget.classList.remove("hidden")
    this.triggerTarget.classList.add("bg-gray-200", "dark:bg-gray-700")
    
    // Mobile animation
    if (window.innerWidth < 1024) {
      // Add backdrop for mobile
      this.addMobileBackdrop()
      
      // Trigger animation after display
      requestAnimationFrame(() => {
        this.dropdownTarget.classList.add("active")
        this.dropdownTarget.classList.remove("translate-y-full")
      })
    }
    
    // Dispatch event to notify other dropdowns
    window.dispatchEvent(new CustomEvent('dropdown:opened', { detail: { controller: this } }))
  }
  
  close() {
    // Mobile animation
    if (window.innerWidth < 1024) {
      this.dropdownTarget.classList.remove("active")
      this.dropdownTarget.classList.add("translate-y-full")
      
      // Hide after animation
      setTimeout(() => {
        this.dropdownTarget.classList.add("hidden")
        this.removeMobileBackdrop()
      }, 300)
    } else {
      this.dropdownTarget.classList.add("hidden")
    }
    
    this.triggerTarget.classList.remove("bg-gray-200", "dark:bg-gray-700")
  }
  
  addMobileBackdrop() {
    if (!this.backdrop) {
      this.backdrop = document.createElement('div')
      this.backdrop.className = 'fixed inset-0 bg-black bg-opacity-50 z-40'
      this.backdrop.addEventListener('click', () => this.close())
      document.body.appendChild(this.backdrop)
    }
  }
  
  removeMobileBackdrop() {
    if (this.backdrop) {
      this.backdrop.remove()
      this.backdrop = null
    }
  }
  
  closeOnClickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.close()
    }
  }
  
  backToWorkspace(event) {
    event.preventDefault()
    window.location.href = '/account'
    this.close()
  }
  
  winFreeCredits(event) {
    event.preventDefault()
    console.log("Opening free credits...")
    this.close()
  }
  
  viewDocumentation(event) {
    event.preventDefault()
    window.open('https://docs.overskill.app', '_blank')
    this.close()
  }
  
  manageBilling(event) {
    event.preventDefault()
    console.log("Opening billing...")
    this.close()
  }
  
  getHelp(event) {
    event.preventDefault()
    console.log("Opening help center...")
    this.close()
  }
  
  upgradePlan(event) {
    event.preventDefault()
    console.log("Opening upgrade plan...")
    this.close()
  }
  
  signOut(event) {
    event.preventDefault()
    window.location.href = '/users/sign_out'
    this.close()
  }
}