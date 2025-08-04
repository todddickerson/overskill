import { Controller } from "@hotwired/stimulus"

// Controller for main navigation between Dashboard and Preview
export default class extends Controller {
  static targets = ["tab", "panel", "previewControls"]
  
  connect() {
    // Set initial active tab to preview
    this.showPanel('preview')
    
    // Check if we're on mobile
    const isMobile = window.innerWidth < 1024
    
    // Update tab styling to match initial state
    this.tabTargets.forEach(tab => {
      if (tab.dataset.panel === 'preview') {
        if (isMobile) {
          tab.classList.remove('text-gray-600', 'dark:text-gray-400', 'bg-transparent')
          tab.classList.add('text-gray-900', 'dark:text-white', 'bg-white', 'dark:bg-gray-800', 'shadow-sm')
        } else {
          tab.classList.remove('text-gray-600', 'dark:text-gray-400', 'border-transparent')
          tab.classList.add('text-gray-900', 'dark:text-white', 'border-primary-500')
        }
      } else {
        if (isMobile) {
          tab.classList.remove('text-gray-900', 'dark:text-white', 'bg-white', 'dark:bg-gray-800', 'shadow-sm')
          tab.classList.add('text-gray-600', 'dark:text-gray-400', 'bg-transparent')
        } else {
          tab.classList.remove('text-gray-900', 'dark:text-white', 'border-primary-500')
          tab.classList.add('text-gray-600', 'dark:text-gray-400', 'border-transparent')
        }
      }
    })
  }
  
  switchTab(event) {
    const button = event.currentTarget
    const panelName = button.dataset.panel
    
    // Check if we're on mobile
    const isMobile = window.innerWidth < 1024
    
    // Update active tab styling
    this.tabTargets.forEach(tab => {
      if (tab === button) {
        if (isMobile) {
          // Mobile styling - pill button
          tab.classList.remove('text-gray-600', 'dark:text-gray-400', 'bg-transparent')
          tab.classList.add('text-gray-900', 'dark:text-white', 'bg-white', 'dark:bg-gray-800', 'shadow-sm')
        } else {
          // Desktop styling - underline
          tab.classList.remove('text-gray-600', 'dark:text-gray-400', 'border-transparent')
          tab.classList.add('text-gray-900', 'dark:text-white', 'border-primary-500')
        }
      } else {
        if (isMobile) {
          // Mobile styling - pill button
          tab.classList.remove('text-gray-900', 'dark:text-white', 'bg-white', 'dark:bg-gray-800', 'shadow-sm')
          tab.classList.add('text-gray-600', 'dark:text-gray-400', 'bg-transparent')
        } else {
          // Desktop styling - underline
          tab.classList.remove('text-gray-900', 'dark:text-white', 'border-primary-500')
          tab.classList.add('text-gray-600', 'dark:text-gray-400', 'border-transparent')
        }
      }
    })
    
    // Show the selected panel
    this.showPanel(panelName)
  }
  
  showPanel(panelName) {
    this.panelTargets.forEach(panel => {
      if (panel.dataset.panelName === panelName) {
        panel.classList.remove('hidden')
      } else {
        panel.classList.add('hidden')
      }
    })
    
    // Show/hide preview controls based on active panel
    if (this.hasPreviewControlsTarget) {
      if (panelName === 'preview') {
        this.previewControlsTarget.classList.remove('hidden')
      } else {
        this.previewControlsTarget.classList.add('hidden')
      }
    }
  }
}