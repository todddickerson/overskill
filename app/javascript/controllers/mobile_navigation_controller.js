import { Controller } from "@hotwired/stimulus"

// Controller for mobile-specific navigation and mode switching
export default class extends Controller {
  static targets = [
    "chatPanel", "previewPanel", "dashboardPanel",
    "chatTab", "previewTab",
    "leftAction", "rightAction",
    "plusIcon", "historyIcon", "settingsIcon", "publishIcon",
    "previewControls", "controlStyleToggle",
    "boxedIcon", "overlayIcon"
  ]
  
  static values = { 
    currentMode: String,
    controlStyle: { type: String, default: "overlay" }
  }
  
  connect() {
    // Set initial mode based on data attribute or default
    this.currentModeValue = this.currentModeValue || "preview"
    this.updateUIForMode()
    
    // Add class to body for mobile-specific styling
    if (window.innerWidth < 1024) {
      document.body.classList.add('mobile-editor')
    }
  }
  
  disconnect() {
    document.body.classList.remove('mobile-editor')
  }
  
  // Mode switching
  showChat() {
    this.currentModeValue = "chat"
    this.updateUIForMode()
  }
  
  showPreview() {
    this.currentModeValue = "preview"
    this.updateUIForMode()
  }
  
  showDashboard() {
    this.currentModeValue = "dashboard"
    this.updateUIForMode()
  }
  
  updateUIForMode() {
    // Update tab styling
    if (this.hasChatTabTarget && this.hasPreviewTabTarget) {
      if (this.currentModeValue === "chat") {
        this.chatTabTarget.classList.add('bg-white', 'dark:bg-gray-800', 'shadow-sm')
        this.chatTabTarget.classList.remove('text-gray-600', 'dark:text-gray-400')
        this.previewTabTarget.classList.remove('bg-white', 'dark:bg-gray-800', 'shadow-sm')
        this.previewTabTarget.classList.add('text-gray-600', 'dark:text-gray-400')
      } else {
        this.previewTabTarget.classList.add('bg-white', 'dark:bg-gray-800', 'shadow-sm')
        this.previewTabTarget.classList.remove('text-gray-600', 'dark:text-gray-400')
        this.chatTabTarget.classList.remove('bg-white', 'dark:bg-gray-800', 'shadow-sm')
        this.chatTabTarget.classList.add('text-gray-600', 'dark:text-gray-400')
      }
    }
    
    // Update panels visibility
    this.updatePanelVisibility()
    
    // Update action buttons
    this.updateActionButtons()
    
    // Show/hide preview controls
    if (this.hasPreviewControlsTarget) {
      if (this.currentModeValue === "preview") {
        this.previewControlsTarget.classList.remove('hidden')
      } else {
        this.previewControlsTarget.classList.add('hidden')
      }
    }
  }
  
  updatePanelVisibility() {
    // Hide all panels first
    if (this.hasChatPanelTarget) {
      this.chatPanelTarget.classList.add('hidden')
      this.chatPanelTarget.classList.remove('flex')
    }
    if (this.hasPreviewPanelTarget) {
      this.previewPanelTarget.classList.add('hidden')
    }
    if (this.hasDashboardPanelTarget) {
      this.dashboardPanelTarget.classList.add('hidden')
    }
    
    // Show active panel
    switch (this.currentModeValue) {
      case "chat":
        if (this.hasChatPanelTarget) {
          this.chatPanelTarget.classList.remove('hidden')
          this.chatPanelTarget.classList.add('flex')
          // Make chat full screen on mobile
          this.chatPanelTarget.classList.add('fixed', 'inset-0', 'top-14', 'bottom-16', 'z-20')
        }
        break
      case "preview":
        if (this.hasPreviewPanelTarget) {
          this.previewPanelTarget.classList.remove('hidden')
        }
        break
      case "dashboard":
        if (this.hasDashboardPanelTarget) {
          this.dashboardPanelTarget.classList.remove('hidden')
        }
        break
    }
  }
  
  updateActionButtons() {
    // Update left button
    if (this.hasPlusIconTarget && this.hasHistoryIconTarget) {
      if (this.currentModeValue === "chat") {
        this.plusIconTarget.classList.remove('hidden')
        this.historyIconTarget.classList.add('hidden')
      } else {
        this.plusIconTarget.classList.add('hidden')
        this.historyIconTarget.classList.remove('hidden')
      }
    }
    
    // Update right button
    if (this.hasSettingsIconTarget && this.hasPublishIconTarget) {
      if (this.currentModeValue === "chat") {
        this.settingsIconTarget.classList.remove('hidden')
        this.publishIconTarget.classList.add('hidden')
      } else {
        this.settingsIconTarget.classList.add('hidden')
        this.publishIconTarget.classList.remove('hidden')
      }
    }
  }
  
  // Action handlers
  handleLeftAction() {
    if (this.currentModeValue === "chat") {
      this.openPlusMenu()
    } else {
      this.openVersionHistory()
    }
  }
  
  handleRightAction() {
    if (this.currentModeValue === "chat") {
      this.openSettings()
    } else {
      this.openPublishModal()
    }
  }
  
  openPlusMenu() {
    // Create and show plus menu modal
    const modal = this.createMobileModal('Plus Menu', this.buildPlusMenuContent())
    document.body.appendChild(modal)
    requestAnimationFrame(() => {
      modal.classList.add('active')
    })
  }
  
  openVersionHistory() {
    // Trigger existing version history modal
    const versionHistoryModal = document.querySelector('[data-version-history-target="modal"]')
    if (versionHistoryModal) {
      versionHistoryModal.classList.remove('hidden')
    }
  }
  
  openSettings() {
    // Switch to dashboard mode
    this.showDashboard()
  }
  
  openPublishModal() {
    // Trigger existing publish modal
    const publishController = this.application.getControllerForElementAndIdentifier(
      document.querySelector('[data-controller*="publish-modal"]'),
      'publish-modal'
    )
    if (publishController) {
      publishController.open()
    }
  }
  
  // Preview control actions
  openPageSelector() {
    // Create page selector modal
    const modal = this.createMobileModal('Select Page', this.buildPageSelectorContent())
    document.body.appendChild(modal)
    requestAnimationFrame(() => {
      modal.classList.add('active')
    })
  }
  
  refreshPreview() {
    // Reload preview iframe
    const iframe = document.querySelector('[data-preview-target="frame"]')
    if (iframe) {
      iframe.src = iframe.src
    }
  }
  
  openInNewTab() {
    // Open preview in new tab
    const iframe = document.querySelector('[data-preview-target="frame"]')
    if (iframe) {
      window.open(iframe.src, '_blank')
    }
  }
  
  toggleControlStyle() {
    this.controlStyleValue = this.controlStyleValue === "overlay" ? "boxed" : "overlay"
    
    // Update icons
    if (this.hasBoxedIconTarget && this.hasOverlayIconTarget) {
      if (this.controlStyleValue === "overlay") {
        this.boxedIconTarget.classList.remove('hidden')
        this.overlayIconTarget.classList.add('hidden')
      } else {
        this.boxedIconTarget.classList.add('hidden')
        this.overlayIconTarget.classList.remove('hidden')
      }
    }
    
    // Apply control style to preview
    if (this.hasPreviewControlsTarget) {
      if (this.controlStyleValue === "boxed") {
        this.previewControlsTarget.classList.remove('fixed', 'bg-white/90', 'dark:bg-gray-800/90', 'backdrop-blur-sm')
        this.previewControlsTarget.classList.add('relative', 'bg-white', 'dark:bg-gray-800')
      } else {
        this.previewControlsTarget.classList.add('fixed', 'bg-white/90', 'dark:bg-gray-800/90', 'backdrop-blur-sm')
        this.previewControlsTarget.classList.remove('relative', 'bg-white', 'dark:bg-gray-800')
      }
    }
  }
  
  // Modal creation helper
  createMobileModal(title, content) {
    const modal = document.createElement('div')
    modal.className = 'mobile-modal fixed inset-x-0 bottom-0 bg-white dark:bg-gray-800 rounded-t-2xl shadow-2xl z-50 transform translate-y-full transition-transform duration-300 ease-out'
    modal.innerHTML = `
      <div class="flex flex-col max-h-[90vh]">
        <!-- Header -->
        <div class="flex items-center justify-between px-6 py-4 border-b border-gray-200 dark:border-gray-700">
          <h3 class="text-lg font-semibold text-gray-900 dark:text-white">${title}</h3>
          <button class="p-2 text-gray-400 hover:text-gray-600 dark:hover:text-gray-300" data-action="click->mobile-navigation#closeModal">
            <i class="fas fa-times"></i>
          </button>
        </div>
        
        <!-- Content -->
        <div class="flex-1 overflow-y-auto">
          ${content}
        </div>
      </div>
      
      <!-- Backdrop -->
      <div class="fixed inset-0 bg-black bg-opacity-50 -z-10" data-action="click->mobile-navigation#closeModal"></div>
    `
    
    modal.dataset.controller = "mobile-navigation"
    return modal
  }
  
  closeModal(event) {
    const modal = event.target.closest('.mobile-modal')
    if (modal) {
      modal.classList.remove('active')
      setTimeout(() => modal.remove(), 300)
    }
  }
  
  // Content builders
  buildPlusMenuContent() {
    return `
      <div class="p-6 space-y-4">
        <button class="w-full flex items-center space-x-3 p-4 bg-gray-50 dark:bg-gray-700 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-600 transition-colors text-left">
          <i class="fas fa-plus-circle text-blue-500 text-lg"></i>
          <div>
            <div class="font-medium text-gray-900 dark:text-white">New Component</div>
            <div class="text-sm text-gray-500 dark:text-gray-400">Add a new UI component</div>
          </div>
        </button>
        
        <button class="w-full flex items-center space-x-3 p-4 bg-gray-50 dark:bg-gray-700 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-600 transition-colors text-left">
          <i class="fas fa-file-import text-green-500 text-lg"></i>
          <div>
            <div class="font-medium text-gray-900 dark:text-white">Import Code</div>
            <div class="text-sm text-gray-500 dark:text-gray-400">Import existing code or templates</div>
          </div>
        </button>
        
        <button class="w-full flex items-center space-x-3 p-4 bg-gray-50 dark:bg-gray-700 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-600 transition-colors text-left">
          <i class="fas fa-database text-purple-500 text-lg"></i>
          <div>
            <div class="font-medium text-gray-900 dark:text-white">Database Action</div>
            <div class="text-sm text-gray-500 dark:text-gray-400">Create tables or modify schema</div>
          </div>
        </button>
        
        <button class="w-full flex items-center space-x-3 p-4 bg-gray-50 dark:bg-gray-700 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-600 transition-colors text-left">
          <i class="fas fa-lightbulb text-yellow-500 text-lg"></i>
          <div>
            <div class="font-medium text-gray-900 dark:text-white">AI Suggestions</div>
            <div class="text-sm text-gray-500 dark:text-gray-400">Get AI-powered feature ideas</div>
          </div>
        </button>
      </div>
    `
  }
  
  buildPageSelectorContent() {
    return `
      <div class="p-4 space-y-2">
        <button class="w-full text-left px-4 py-3 hover:bg-gray-50 dark:hover:bg-gray-700 rounded-lg transition-colors">
          <div class="flex items-center justify-between">
            <span class="text-gray-900 dark:text-white">Home</span>
            <i class="fas fa-check text-blue-500"></i>
          </div>
        </button>
        
        <button class="w-full text-left px-4 py-3 hover:bg-gray-50 dark:hover:bg-gray-700 rounded-lg transition-colors">
          <span class="text-gray-900 dark:text-white">About</span>
        </button>
        
        <button class="w-full text-left px-4 py-3 hover:bg-gray-50 dark:hover:bg-gray-700 rounded-lg transition-colors">
          <span class="text-gray-900 dark:text-white">Contact</span>
        </button>
        
        <button class="w-full text-left px-4 py-3 hover:bg-gray-50 dark:hover:bg-gray-700 rounded-lg transition-colors">
          <span class="text-gray-900 dark:text-white">Dashboard</span>
        </button>
      </div>
    `
  }
}