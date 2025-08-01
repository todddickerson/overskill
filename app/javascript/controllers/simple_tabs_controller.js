import { Controller } from "@hotwired/stimulus"

// Simplified tabs controller for debugging
export default class extends Controller {
  static targets = ["tab", "panel"]

  connect() {
    console.log("SimpleTabs connected!", {
      tabs: this.tabTargets.length,
      panels: this.panelTargets.length
    })
    
    // Show initial tab
    const urlParams = new URLSearchParams(window.location.search)
    const activeTab = urlParams.get('tab') || 'preview'
    this.showTab(activeTab)
  }

  switchTab(event) {
    event.preventDefault()
    const tabName = event.currentTarget.dataset.panel
    console.log("Tab clicked:", tabName)
    this.showTab(tabName)
  }

  showTab(tabName) {
    // Update tabs appearance
    this.tabTargets.forEach(tab => {
      const isActive = tab.dataset.panel === tabName
      tab.classList.toggle("text-white", isActive)
      tab.classList.toggle("text-gray-400", !isActive)
      tab.classList.toggle("border-primary-500", isActive)
      tab.classList.toggle("border-transparent", !isActive)
    })

    // Show/hide panels
    this.panelTargets.forEach(panel => {
      const shouldShow = panel.dataset.panelName === tabName
      panel.classList.toggle("hidden", !shouldShow)
    })

    // Update URL
    const url = new URL(window.location)
    url.searchParams.set('tab', tabName)
    window.history.replaceState({}, '', url)
  }
}