import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal"]
  
  open() {
    console.log('HelpModalController.open() called')
    if (this.hasModalTarget) {
      this.modalTarget.classList.remove("hidden")
      document.body.style.overflow = "hidden"
    }
  }
  
  close(event) {
    if (event) event.preventDefault()
    if (this.hasModalTarget) {
      this.modalTarget.classList.add("hidden")
      document.body.style.overflow = ""
    }
  }
  
  // Close modal when clicking outside
  closeOnBackdrop(event) {
    if (event.target === this.modalTarget) {
      this.close()
    }
  }
}