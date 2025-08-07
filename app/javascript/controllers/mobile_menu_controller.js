import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "hamburger", "close"]

  toggle() {
    if (this.panelTarget.classList.contains("hidden")) {
      this.open()
    } else {
      this.close()
    }
  }

  open() {
    this.panelTarget.classList.remove("hidden")
    this.hamburgerTarget.classList.add("hidden")
    this.closeTarget.classList.remove("hidden")
  }

  close() {
    this.panelTarget.classList.add("hidden")
    this.hamburgerTarget.classList.remove("hidden")
    this.closeTarget.classList.add("hidden")
  }
}