import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "panel"]
  static values = { defaultTab: String }
  
  connect() {
    // Check for anchor in URL for deep linking
    this.handleDeepLink()
    
    // Listen for hash changes
    window.addEventListener('hashchange', this.handleDeepLink.bind(this))
  }
  
  disconnect() {
    window.removeEventListener('hashchange', this.handleDeepLink.bind(this))
  }
  
  handleDeepLink() {
    const hash = window.location.hash
    
    // Check if we have a dashboard deep link
    if (hash && hash.startsWith('#dashboard-')) {
      const tabName = hash.replace('#dashboard-', '')
      this.activateTab(tabName)
    } else if (!hash && this.defaultTabValue) {
      // No hash, use default
      this.activateTab(this.defaultTabValue)
    }
  }
  
  activateTab(tabName) {
    // Find the tab button with matching data-panel
    const tabButton = this.tabTargets.find(tab => tab.dataset.panel === tabName)
    
    if (tabButton) {
      // Simulate click on the tab
      tabButton.click()
      
      // Ensure the dashboard tab in main editor is also active
      const mainDashboardTab = document.querySelector('[data-panel="dashboard"]')
      if (mainDashboardTab && !mainDashboardTab.classList.contains('border-primary-500')) {
        mainDashboardTab.click()
      }
    }
  }
  
  switchTab(event) {
    const selectedTab = event.currentTarget
    const panelName = selectedTab.dataset.panel
    
    // Update URL hash for deep linking
    window.location.hash = `dashboard-${panelName}`
    
    // Update active tab styling
    this.tabTargets.forEach(tab => {
      if (tab === selectedTab) {
        tab.classList.add('bg-gray-100', 'dark:bg-gray-700', 'text-gray-900', 'dark:text-white', 'border-r-2', 'border-primary-500')
        tab.classList.remove('text-gray-600', 'dark:text-gray-400', 'hover:bg-gray-50', 'dark:hover:bg-gray-700')
      } else {
        tab.classList.remove('bg-gray-100', 'dark:bg-gray-700', 'text-gray-900', 'dark:text-white', 'border-r-2', 'border-primary-500')
        tab.classList.add('text-gray-600', 'dark:text-gray-400', 'hover:bg-gray-50', 'dark:hover:bg-gray-700')
      }
    })
    
    // Show/hide panels
    this.panelTargets.forEach(panel => {
      if (panel.dataset.panelName === panelName) {
        panel.classList.remove('hidden')
      } else {
        panel.classList.add('hidden')
      }
    })
  }
}