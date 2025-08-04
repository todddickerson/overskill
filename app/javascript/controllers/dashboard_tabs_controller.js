import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "panel"]

  connect() {
    // Initialize first tab as active
    this.switchToTab("overview")
  }

  switchTab(event) {
    const clickedPanel = event.currentTarget.dataset.panel
    this.switchToTab(clickedPanel)
  }

  switchToTab(panelName) {
    // Update tab states
    this.tabTargets.forEach(tab => {
      const tabPanel = tab.dataset.panel
      if (tabPanel === panelName) {
        // Active tab styling
        tab.classList.remove('text-gray-600', 'dark:text-gray-400', 'hover:text-gray-900', 'dark:hover:text-white', 'hover:bg-gray-50', 'dark:hover:bg-gray-700')
        tab.classList.add('text-gray-900', 'dark:text-white', 'bg-gray-100', 'dark:bg-gray-700', 'border-r-2', 'border-primary-500')
      } else {
        // Inactive tab styling
        tab.classList.remove('text-gray-900', 'dark:text-white', 'bg-gray-100', 'dark:bg-gray-700', 'border-r-2', 'border-primary-500')
        tab.classList.add('text-gray-600', 'dark:text-gray-400', 'hover:text-gray-900', 'dark:hover:text-white', 'hover:bg-gray-50', 'dark:hover:bg-gray-700')
      }
    })

    // Update panel visibility
    this.panelTargets.forEach(panel => {
      const currentPanelName = panel.dataset.panelName
      if (currentPanelName === panelName) {
        panel.classList.remove('hidden')
      } else {
        panel.classList.add('hidden')
      }
    })
  }
}