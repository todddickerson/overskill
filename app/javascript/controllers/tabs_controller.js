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
    console.log("Switching to panel:", panelName)
    console.log("Panel targets found:", this.panelTargets.length)
    
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
      console.log("Panel:", panel.dataset.panelName, "Hidden:", panel.classList.contains("hidden"))
      if (panel.dataset.panelName === panelName) {
        panel.classList.remove("hidden")
      } else {
        panel.classList.add("hidden")
      }
    })
  }
}