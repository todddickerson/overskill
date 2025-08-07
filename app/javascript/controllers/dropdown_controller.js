import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu", "button"]

  connect() {
    this.menuTarget.classList.add("hidden")
  }

  toggle(event) {
    event.stopPropagation()
    if (this.menuTarget.classList.contains("hidden")) {
      this.show()
    } else {
      this.hide()
    }
  }

  show() {
    this.menuTarget.classList.remove("hidden")
    // Add click outside listener
    setTimeout(() => {
      document.addEventListener('click', this.hideOnClickOutside)
    }, 0)
  }

  hide() {
    this.menuTarget.classList.add("hidden")
    // Remove click outside listener
    document.removeEventListener('click', this.hideOnClickOutside)
  }

  hideOnClickOutside = (event) => {
    if (!this.element.contains(event.target)) {
      this.hide()
    }
  }

  disconnect() {
    document.removeEventListener('click', this.hideOnClickOutside)
  }
}