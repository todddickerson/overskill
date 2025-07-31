import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "panel"]

  connect() {
    // Show the first tab by default
    this.showPanel("preview")
  }

  switchTab(event) {
    event.preventDefault()
    const panel = event.currentTarget.dataset.panel
    this.showPanel(panel)
  }

  showPanel(panelName) {
    // Update tabs
    this.tabTargets.forEach(tab => {
      if (tab.dataset.panel === panelName) {
        tab.classList.remove("text-gray-400", "border-transparent")
        tab.classList.add("text-white", "border-primary-500")
      } else {
        tab.classList.remove("text-white", "border-primary-500")
        tab.classList.add("text-gray-400", "border-transparent")
      }
    })

    // Update panels
    this.panelTargets.forEach(panel => {
      if (panel.dataset.panelName === panelName) {
        panel.classList.remove("hidden")
      } else {
        panel.classList.add("hidden")
      }
    })
  }
}