import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "panel"]

  connect() {
    // Show the first panel by default
    this.showPanel("preview")
  }

  switchTab(event) {
    const panelName = event.currentTarget.dataset.panel
    this.showPanel(panelName)
  }

  showPanel(panelName) {
    // Update tabs
    this.tabTargets.forEach(tab => {
      if (tab.dataset.panel === panelName) {
        tab.classList.remove("text-gray-400", "border-transparent")
        tab.classList.add("text-white", "border-primary-500")
      } else {
        tab.classList.add("text-gray-400", "border-transparent")
        tab.classList.remove("text-white", "border-primary-500")
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