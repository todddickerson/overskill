import { Controller } from "@hotwired/stimulus"

// Controller for dashboard subnav navigation
export default class extends Controller {
  static targets = ["nav"]
  static values = { currentView: String }
  
  connect() {
    // Set initial active view
    this.showView(this.currentViewValue || 'overview')
  }
  
  switchView(event) {
    const button = event.currentTarget
    const viewName = button.dataset.dashboardNav
    
    // Update nav button styling within this controller's scope
    const navButtons = this.element.querySelectorAll('[data-dashboard-nav]')
    navButtons.forEach(navButton => {
      if (navButton === button) {
        navButton.classList.remove('text-gray-600', 'dark:text-gray-400', 'hover:bg-gray-50', 'dark:hover:bg-gray-700')
        navButton.classList.add('text-gray-900', 'dark:text-white', 'bg-gray-100', 'dark:bg-gray-700')
      } else {
        navButton.classList.remove('text-gray-900', 'dark:text-white', 'bg-gray-100', 'dark:bg-gray-700')
        navButton.classList.add('text-gray-600', 'dark:text-gray-400', 'hover:bg-gray-50', 'dark:hover:bg-gray-700')
      }
    })
    
    // Show the selected view
    this.showView(viewName)
    this.currentViewValue = viewName
  }
  
  showView(viewName) {
    // Find all dashboard view panels
    const views = this.element.querySelectorAll('[data-dashboard-view]')
    views.forEach(view => {
      if (view.dataset.dashboardView === viewName) {
        view.classList.remove('hidden')
      } else {
        view.classList.add('hidden')
      }
    })
  }
}