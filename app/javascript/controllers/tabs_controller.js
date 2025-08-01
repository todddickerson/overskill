import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "panel", "refreshButton"]

  connect() {
    console.log("🎯 Tabs controller connected!")
    console.log("Found tabs:", this.tabTargets.length)
    console.log("Found panels:", this.panelTargets.length)
    
    // Log details about each panel
    this.panelTargets.forEach((panel, index) => {
      console.log(`Panel ${index}:`, {
        panelName: panel.dataset.panelName,
        hidden: panel.classList.contains("hidden")
      })
    })
    
    // Show the first tab by default (or restore from URL param)
    const urlParams = new URLSearchParams(window.location.search)
    const activeTab = urlParams.get('tab') || 'preview'
    this.showPanel(activeTab)
  }

  disconnect() {
    console.log("🔌 Tabs controller disconnected!")
  }

  switchTab(event) {
    console.log("🖱️ Tab clicked:", event.currentTarget)
    event.preventDefault()
    const panel = event.currentTarget.dataset.panel
    console.log("Requested panel:", panel)
    this.showPanel(panel)
  }

  showPanel(panelName) {
    console.log(`Switching to ${panelName} tab`)
    
    // Update tabs
    this.tabTargets.forEach((tab) => {
      const tabPanel = tab.dataset.panel
      
      if (tabPanel === panelName) {
        tab.classList.remove("text-gray-600", "dark:text-gray-400", "border-transparent")
        tab.classList.add("text-gray-900", "dark:text-white", "border-primary-500")
      } else {
        tab.classList.remove("text-gray-900", "dark:text-white", "border-primary-500")
        tab.classList.add("text-gray-600", "dark:text-gray-400", "border-transparent")
      }
    })

    // Update panels
    this.panelTargets.forEach((panel) => {
      const panelDataName = panel.dataset.panelName
      const shouldShow = panelDataName === panelName
      
      if (shouldShow) {
        panel.classList.remove("hidden")
      } else {
        panel.classList.add("hidden")
      }
    })
    
    // Update URL without page reload
    const url = new URL(window.location)
    url.searchParams.set('tab', panelName)
    window.history.replaceState({}, '', url)
    
    // Show/hide refresh button based on active tab
    if (this.hasRefreshButtonTarget) {
      if (panelName === 'preview') {
        this.refreshButtonTarget.classList.remove('invisible')
      } else {
        this.refreshButtonTarget.classList.add('invisible')
      }
    }
  }
  
  refreshPreview(event) {
    console.log("🔄 Refreshing preview...")
    
    // Find the preview iframe
    const iframe = this.element.querySelector('iframe')
    if (iframe) {
      // Add spinning animation to button
      const icon = this.refreshButtonTarget.querySelector('i')
      if (icon) {
        icon.classList.add('fa-spin')
      }
      
      // Reload the iframe
      iframe.src = iframe.src
      
      // Remove spinning animation after a delay
      setTimeout(() => {
        if (icon) {
          icon.classList.remove('fa-spin')
        }
      }, 1000)
    }
  }
}