import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["overlay"]
  
  toggle() {
    if (this.hasOverlayTarget) {
      this.overlayTarget.classList.toggle("hidden")
    }
  }
  
  close() {
    if (this.hasOverlayTarget) {
      this.overlayTarget.classList.add("hidden")
    }
  }
  
  open() {
    if (this.hasOverlayTarget) {
      this.overlayTarget.classList.remove("hidden")
    }
  }
}