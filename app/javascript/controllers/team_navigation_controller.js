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
    this.triggerTarget.classList.add("bg-gray-200", "dark:bg-gray-700")
  }
  
  close() {
    this.dropdownTarget.classList.add("hidden")
    this.triggerTarget.classList.remove("bg-gray-200", "dark:bg-gray-700")
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