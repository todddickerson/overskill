import { Controller } from "@hotwired/stimulus"

// Controller for mobile-specific navigation and mode switching
export default class extends Controller {
  static targets = [
    "chatTab", "previewTab", "dashboardTab",
    "leftAction", "rightAction",
    "plusIcon", "historyIcon", "menuIcon", 
    "infoIcon", "publishIcon", "saveIcon",
    "previewControls", "chatInput", "currentPageName"
  ]
  
  static values = { 
    currentMode: String,
    controlStyle: { type: String, default: "overlay" }
  }
  
  connect() {
    console.log('MobileNavigationController connected')
    console.log('Controller element:', this.element)
    
    // Store panel references by ID
    this.panels = {
      chat: document.getElementById('chat_panel'),
      preview: document.getElementById('preview_panel'),
      dashboard: document.getElementById('dashboard_panel')
    }
    
    console.log('Found panels:', this.panels)
    
    // Use requestAnimationFrame to ensure DOM is ready
    requestAnimationFrame(() => {
      console.log('After frame - Available targets:', {
        hasChatTab: this.hasChatTabTarget,
        hasPreviewTab: this.hasPreviewTabTarget,
        hasDashboardTab: this.hasDashboardTabTarget
      })
      
      // Set initial mode based on data attribute or default
      this.currentModeValue = this.currentModeValue || "preview"
      console.log('Initial mode:', this.currentModeValue)
      this.updateUIForMode()
    })
    
    // Add class to body for mobile-specific styling
    if (window.innerWidth < 1024) {
      document.body.classList.add('mobile-editor')
    }
    
    // Make this controller available globally for AI suggestions
    window.mobileNav = this
  }
  
  disconnect() {
    document.body.classList.remove('mobile-editor')
    window.mobileNav = null
  }
  
  // Debug helper
  debugToggle() {
    console.log('=== Debug Toggle Test ===')
    console.log('Current mode:', this.currentModeValue)
    console.log('Panels:', this.panels)
    console.log('Tab targets:', {
      hasChatTab: this.hasChatTabTarget,
      hasPreviewTab: this.hasPreviewTabTarget,
      hasDashboardTab: this.hasDashboardTabTarget
    })
    
    // Try to manually show chat
    console.log('Attempting to show chat...')
    this.showChat()
    
    setTimeout(() => {
      console.log('After showChat - current mode:', this.currentModeValue)
      console.log('Chat panel visible?', this.panels.chat && !this.panels.chat.classList.contains('hidden'))
    }, 100)
  }
  
  // Mode switching
  showChat(event) {
    console.log('showChat() called', event)
    console.log('Button clicked:', event?.currentTarget)
    this.currentModeValue = "chat"
    console.log('Current mode set to:', this.currentModeValue)
    this.updateUIForMode()
  }
  
  showPreview(event) {
    console.log('showPreview() called', event)
    console.log('Button clicked:', event?.currentTarget)
    this.currentModeValue = "preview"
    console.log('Current mode set to:', this.currentModeValue)
    this.updateUIForMode()
  }
  
  showDashboard(event) {
    console.log('showDashboard() called', event)
    console.log('Button clicked:', event?.currentTarget)
    this.currentModeValue = "dashboard"
    console.log('Current mode set to:', this.currentModeValue)
    this.updateUIForMode()
  }
  
  updateUIForMode() {
    console.log('updateUIForMode() called with mode:', this.currentModeValue)
    
    // Update tab styling for 3-way toggle - check each individually
    console.log('Tab target status:', {
      hasChatTab: this.hasChatTabTarget,
      hasPreviewTab: this.hasPreviewTabTarget,
      hasDashboardTab: this.hasDashboardTabTarget
    })
    
    // Reset all tabs if they exist
    if (this.hasChatTabTarget) {
      this.chatTabTarget.classList.remove('bg-white', 'dark:bg-gray-800', 'shadow-sm')
      this.chatTabTarget.classList.add('text-gray-600', 'dark:text-gray-400')
    }
    if (this.hasPreviewTabTarget) {
      this.previewTabTarget.classList.remove('bg-white', 'dark:bg-gray-800', 'shadow-sm')
      this.previewTabTarget.classList.add('text-gray-600', 'dark:text-gray-400')
    }
    if (this.hasDashboardTabTarget) {
      this.dashboardTabTarget.classList.remove('bg-white', 'dark:bg-gray-800', 'shadow-sm')
      this.dashboardTabTarget.classList.add('text-gray-600', 'dark:text-gray-400')
    }
    
    // Highlight active tab
    switch (this.currentModeValue) {
      case "chat":
        if (this.hasChatTabTarget) {
          this.chatTabTarget.classList.add('bg-white', 'dark:bg-gray-800', 'shadow-sm')
          this.chatTabTarget.classList.remove('text-gray-600', 'dark:text-gray-400')
        }
        break
      case "preview":
        if (this.hasPreviewTabTarget) {
          this.previewTabTarget.classList.add('bg-white', 'dark:bg-gray-800', 'shadow-sm')
          this.previewTabTarget.classList.remove('text-gray-600', 'dark:text-gray-400')
        }
        break
      case "dashboard":
        if (this.hasDashboardTabTarget) {
          this.dashboardTabTarget.classList.add('bg-white', 'dark:bg-gray-800', 'shadow-sm')
          this.dashboardTabTarget.classList.remove('text-gray-600', 'dark:text-gray-400')
        }
        break
    }
    
    // Update panels visibility
    this.updatePanelVisibility()
    
    // Update action buttons
    this.updateActionButtons()
    
    // Show/hide preview controls and chat input based on mode
    if (this.hasPreviewControlsTarget) {
      if (this.currentModeValue === "preview") {
        this.previewControlsTarget.classList.remove('hidden')
      } else {
        this.previewControlsTarget.classList.add('hidden')
      }
    }
    
    if (this.hasChatInputTarget) {
      if (this.currentModeValue === "chat") {
        this.chatInputTarget.classList.remove('hidden')
      } else {
        this.chatInputTarget.classList.add('hidden')
      }
    }
  }
  
  updatePanelVisibility() {
    // Check if we're on mobile
    const isMobile = window.innerWidth < 1024
    
    if (isMobile && this.panels) {
      // Log panel states
      console.log(`Mobile mode: ${this.currentModeValue}`)
      console.log('Panels:', this.panels)
      
      // Hide all panels first
      Object.values(this.panels).forEach(panel => {
        if (panel) {
          panel.classList.add('hidden')
          panel.classList.remove('flex', 'fixed', 'inset-0', 'top-14', 'bottom-16', 'z-20', 'lg:flex')
          panel.style.display = ''
        }
      })
      
      // Show active panel
      console.log('Switching to panel:', this.currentModeValue)
      const activePanel = this.panels[this.currentModeValue]
      
      if (activePanel) {
        console.log(`${this.currentModeValue} panel before:`, activePanel.className)
        
        if (this.currentModeValue === "chat") {
          // Chat needs special mobile styling with higher z-index
          activePanel.classList.remove('hidden', 'lg:flex')
          activePanel.classList.add('flex', 'fixed', 'inset-0', 'top-14', 'bottom-16', 'z-20')
          activePanel.style.display = 'flex'
          // Override the resizable panel width on mobile
          activePanel.style.width = '100%'
          // Remove any bottom padding since input is now in nav
          const chatContainer = activePanel.querySelector('#chat_container')
          if (chatContainer) {
            chatContainer.classList.remove('pb-20')
          }
        } else if (this.currentModeValue === "dashboard") {
          // Dashboard needs similar mobile styling to fill the viewport
          activePanel.classList.remove('hidden')
          activePanel.classList.add('fixed', 'inset-0', 'top-14', 'bottom-16', 'z-10')
          activePanel.style.display = 'block'
          activePanel.style.width = '100%'
          activePanel.style.height = 'calc(100vh - 8rem)' // Account for header and bottom nav
        } else {
          // Preview just needs to be shown
          activePanel.classList.remove('hidden')
        }
        
        console.log(`${this.currentModeValue} panel after:`, activePanel.className)
      } else {
        console.log(`Panel not found for mode: ${this.currentModeValue}`)
      }
    } else if (!isMobile && this.panels && this.panels.chat) {
      // Desktop mode - reset mobile styles for chat panel
      this.panels.chat.style.display = ''
      this.panels.chat.classList.remove('fixed', 'inset-0', 'top-14', 'bottom-16', 'z-20', 'z-50')
      // Restore the resizable panel width (or use default)
      const resizableController = this.application.getControllerForElementAndIdentifier(this.panels.chat, 'resizable-panel')
      if (resizableController && resizableController.defaultWidthValue) {
        this.panels.chat.style.width = `${resizableController.defaultWidthValue}px`
      } else {
        this.panels.chat.style.width = '384px' // fallback to default
      }
    }
  }
  
  updateActionButtons() {
    // Update left button icons
    if (this.hasPlusIconTarget && this.hasHistoryIconTarget && this.hasMenuIconTarget) {
      // Hide all first
      [this.plusIconTarget, this.historyIconTarget, this.menuIconTarget].forEach(icon => {
        icon.classList.add('hidden')
      })
      
      // Show appropriate icon
      switch (this.currentModeValue) {
        case "chat":
          this.plusIconTarget.classList.remove('hidden')
          break
        case "preview":
          this.historyIconTarget.classList.remove('hidden')
          break
        case "dashboard":
          this.menuIconTarget.classList.remove('hidden')
          break
      }
    }
    
    // Update right button icons
    if (this.hasInfoIconTarget && this.hasPublishIconTarget && this.hasSaveIconTarget) {
      // Hide all first
      [this.infoIconTarget, this.publishIconTarget, this.saveIconTarget].forEach(icon => {
        icon.classList.add('hidden')
      })
      
      // Show appropriate icon
      switch (this.currentModeValue) {
        case "chat":
          this.infoIconTarget.classList.remove('hidden')
          break
        case "preview":
          this.publishIconTarget.classList.remove('hidden')
          break
        case "dashboard":
          this.saveIconTarget.classList.remove('hidden')
          break
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
    switch (this.currentModeValue) {
      case "chat":
        this.openAIInfo()
        break
      case "preview":
        this.openPublishModal()
        break
      case "dashboard":
        this.saveDashboardChanges()
        break
    }
  }
  
  openPlusMenu() {
    // Create and show plus menu modal
    const modal = this.createMobileModal('Plus Menu', this.buildPlusMenuContent())
    document.body.appendChild(modal)
    requestAnimationFrame(() => {
      const modalContent = modal.querySelector('.fixed.bottom-0')
      if (modalContent) {
        modalContent.classList.remove('translate-y-full')
        modalContent.classList.add('translate-y-0')
      }
    })
  }
  
  openVersionHistory() {
    // Trigger existing version history modal
    const versionHistoryModal = document.querySelector('[data-version-history-target="modal"]')
    if (versionHistoryModal) {
      versionHistoryModal.classList.remove('hidden')
      // Add mobile-responsive class if on mobile
      if (window.innerWidth < 1024) {
        const modalContainer = versionHistoryModal.querySelector('.flex')
        if (modalContainer) {
          modalContainer.classList.add('modal-mobile-responsive')
        }
      }
    }
  }
  
  openSettings() {
    // Switch to dashboard mode
    this.showDashboard()
  }
  
  openAIInfo() {
    // Show AI capabilities info modal
    const modal = this.createMobileModal('AI Assistant Info', `
      <div class="p-6 space-y-4">
        <div class="flex items-center space-x-3 mb-4">
          <div class="w-12 h-12 bg-gradient-to-br from-blue-500 to-purple-600 rounded-full flex items-center justify-center">
            <i class="fas fa-sparkles text-white text-lg"></i>
          </div>
          <div>
            <h3 class="text-lg font-semibold text-gray-900 dark:text-white">AI Assistant</h3>
            <p class="text-sm text-gray-600 dark:text-gray-400">Powered by Kimi K2</p>
          </div>
        </div>
        
        <div class="space-y-3">
          <div class="bg-gray-50 dark:bg-gray-700 rounded-lg p-4">
            <h4 class="text-sm font-medium text-gray-900 dark:text-white mb-2">Capabilities</h4>
            <ul class="space-y-2 text-sm text-gray-600 dark:text-gray-300">
              <li class="flex items-start space-x-2">
                <i class="fas fa-check-circle text-green-500 mt-0.5"></i>
                <span>Create complete web applications from descriptions</span>
              </li>
              <li class="flex items-start space-x-2">
                <i class="fas fa-check-circle text-green-500 mt-0.5"></i>
                <span>Update and modify existing code</span>
              </li>
              <li class="flex items-start space-x-2">
                <i class="fas fa-check-circle text-green-500 mt-0.5"></i>
                <span>Debug and fix issues automatically</span>
              </li>
              <li class="flex items-start space-x-2">
                <i class="fas fa-check-circle text-green-500 mt-0.5"></i>
                <span>Add features and improve designs</span>
              </li>
            </ul>
          </div>
          
          <div class="bg-blue-50 dark:bg-blue-900/20 rounded-lg p-4">
            <p class="text-sm text-blue-700 dark:text-blue-300">
              <i class="fas fa-lightbulb mr-2"></i>
              Tip: Be specific about what you want to build or change. The AI works best with clear, detailed instructions.
            </p>
          </div>
        </div>
      </div>
    `)
    document.body.appendChild(modal)
    requestAnimationFrame(() => {
      modal.classList.add('active')
    })
  }
  
  saveDashboardChanges() {
    // TODO: Implement save functionality
    console.log('Saving dashboard changes...')
  }
  
  goBack() {
    // Go back to preview mode from chat
    this.showPreview()
  }
  
  openPublishModal() {
    console.log('openPublishModal called')
    
    // Try multiple approaches to find and open the publish modal
    const publishModal = document.querySelector('#publish_modal, [data-publish-modal-target="modal"]')
    console.log('Found publish modal:', publishModal)
    
    if (publishModal) {
      // Method 1: Try to get the controller directly
      const publishController = this.application.getControllerForElementAndIdentifier(publishModal, 'publish-modal')
      console.log('Found publish controller:', publishController)
      
      if (publishController && publishController.open) {
        console.log('Calling controller.open()')
        publishController.open()
        return
      }
      
      // Method 2: Try to trigger via button click
      const publishButton = document.querySelector('[data-action*="publish-modal#open"]')
      console.log('Found publish button:', publishButton)
      
      if (publishButton) {
        console.log('Clicking publish button')
        publishButton.click()
        return
      }
      
      // Method 3: Manually show the modal
      console.log('Manually showing modal')
      publishModal.classList.remove('hidden')
    } else {
      console.log('No publish modal found in DOM')
    }
  }
  
  // Preview control actions
  openPageSelector() {
    // Create page selector modal
    const modal = this.createMobileModal('Select Page', this.buildPageSelectorContent())
    document.body.appendChild(modal)
    requestAnimationFrame(() => {
      const modalContent = modal.querySelector('.fixed.bottom-0')
      if (modalContent) {
        modalContent.classList.remove('translate-y-full')
        modalContent.classList.add('translate-y-0')
      }
    })
  }
  
  selectPage(event) {
    const pagePath = event.currentTarget.dataset.pagePath
    if (!pagePath) return
    
    // Update current page display
    this.currentPageFile = pagePath
    if (this.hasCurrentPageNameTarget) {
      this.currentPageNameTarget.textContent = pagePath.split('/').pop()
    }
    
    // Update preview iframe to show selected file
    const iframe = document.querySelector('[data-preview-target="frame"]')
    if (iframe) {
      const appId = this.element.dataset.mobileNavigationAppIdValue
      iframe.src = `/account/apps/${appId}/preview/${pagePath}`
    }
    
    // Close modal
    this.closeModal(event)
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
  
  
  // Modal creation helper
  createMobileModal(title, content) {
    const modal = document.createElement('div')
    modal.className = 'mobile-modal'
    modal.innerHTML = `
      <!-- Backdrop -->
      <div class="fixed inset-0 bg-black bg-opacity-50 z-[60]" data-action="click->mobile-navigation#closeModal"></div>
      
      <!-- Modal Content -->
      <div class="fixed bottom-0 left-0 right-0 w-full bg-white dark:bg-gray-800 rounded-t-2xl shadow-2xl transform translate-y-full transition-transform duration-300 ease-out max-h-[70vh] flex flex-col z-[61]">
        <!-- Header -->
        <div class="flex items-center justify-between px-6 py-4 border-b border-gray-200 dark:border-gray-700">
          <h3 class="text-lg font-semibold text-gray-900 dark:text-white">${title}</h3>
          <button class="p-2 text-gray-400 hover:text-gray-600 dark:hover:text-gray-300 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors" data-action="click->mobile-navigation#closeModal">
            <i class="fas fa-times"></i>
          </button>
        </div>
        
        <!-- Content -->
        <div class="flex-1 overflow-y-auto">
          ${content}
        </div>
      </div>
    `
    
    modal.dataset.controller = "mobile-navigation"
    return modal
  }
  
  closeModal(event) {
    const modal = event.target.closest('.mobile-modal')
    if (modal) {
      const modalContent = modal.querySelector('.relative')
      if (modalContent) {
        modalContent.classList.add('translate-y-full')
        modalContent.classList.remove('translate-y-0')
      }
      setTimeout(() => modal.remove(), 300)
    }
  }
  
  // Handle image upload from camera or gallery
  handleImageUpload(event) {
    const file = event.target.files[0]
    if (file) {
      // Convert to base64 and send to chat
      const reader = new FileReader()
      reader.onload = (e) => {
        const base64Image = e.target.result
        
        // Insert image description request into chat
        const chatTextarea = document.querySelector('textarea[name="app_chat_message[content]"]')
        if (chatTextarea) {
          chatTextarea.value = `I've uploaded an image. Please analyze it and suggest how to implement similar features or design in my app. [Image: ${file.name}]`
          
          // Trigger form submission
          const submitButton = chatTextarea.closest('form').querySelector('button[type="submit"]')
          if (submitButton) {
            submitButton.click()
          }
        }
        
        // Close the plus menu
        this.closeModal({ target: document.querySelector('.mobile-modal') })
      }
      reader.readAsDataURL(file)
    }
  }
  
  // Open AI suggestions modal
  openAISuggestions() {
    // Close current modal first
    this.closeModal({ target: document.querySelector('.mobile-modal') })
    
    // Create AI suggestions modal
    const modal = this.createMobileModal('AI Suggestions', this.buildAISuggestionsContent())
    document.body.appendChild(modal)
    requestAnimationFrame(() => {
      modal.classList.add('active')
    })
  }
  
  // Send AI suggestion to chat
  sendAISuggestion(suggestion) {
    const chatTextarea = document.querySelector('textarea[name="app_chat_message[content]"]')
    if (chatTextarea) {
      chatTextarea.value = suggestion
      
      // Trigger form submission
      const submitButton = chatTextarea.closest('form').querySelector('button[type="submit"]')
      if (submitButton) {
        submitButton.click()
      }
    }
    
    // Close all modals
    document.querySelectorAll('.mobile-modal').forEach(modal => {
      modal.classList.remove('active')
      setTimeout(() => modal.remove(), 300)
    })
  }
  
  // Open invite collaborators modal
  openInviteModal() {
    const modal = this.createMobileModal('Invite Collaborators', this.buildInviteContent())
    document.body.appendChild(modal)
    requestAnimationFrame(() => {
      modal.classList.add('active')
    })
  }
  
  openTeamSettings() {
    // Create team settings modal
    const modal = this.createMobileModal('Team Settings', `
      <div class="p-6 space-y-4">
        <div class="space-y-3">
          <button class="w-full flex items-center justify-between p-3 bg-gray-50 dark:bg-gray-700 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-600 transition-colors">
            <div class="flex items-center space-x-3">
              <i class="fas fa-users text-gray-600 dark:text-gray-400"></i>
              <span class="text-gray-900 dark:text-white">Team Members</span>
            </div>
            <i class="fas fa-chevron-right text-gray-400"></i>
          </button>
          
          <button class="w-full flex items-center justify-between p-3 bg-gray-50 dark:bg-gray-700 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-600 transition-colors">
            <div class="flex items-center space-x-3">
              <i class="fas fa-credit-card text-gray-600 dark:text-gray-400"></i>
              <span class="text-gray-900 dark:text-white">Billing & Plans</span>
            </div>
            <i class="fas fa-chevron-right text-gray-400"></i>
          </button>
          
          <button class="w-full flex items-center justify-between p-3 bg-gray-50 dark:bg-gray-700 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-600 transition-colors">
            <div class="flex items-center space-x-3">
              <i class="fas fa-cog text-gray-600 dark:text-gray-400"></i>
              <span class="text-gray-900 dark:text-white">Team Settings</span>
            </div>
            <i class="fas fa-chevron-right text-gray-400"></i>
          </button>
          
          <button class="w-full flex items-center justify-between p-3 bg-gray-50 dark:bg-gray-700 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-600 transition-colors">
            <div class="flex items-center space-x-3">
              <i class="fas fa-plus-circle text-gray-600 dark:text-gray-400"></i>
              <span class="text-gray-900 dark:text-white">Create New App</span>
            </div>
            <i class="fas fa-chevron-right text-gray-400"></i>
          </button>
        </div>
        
        <div class="pt-4 border-t border-gray-200 dark:border-gray-700">
          <button class="w-full flex items-center justify-between p-3 text-red-600 hover:bg-red-50 dark:hover:bg-red-900/20 rounded-lg transition-colors">
            <div class="flex items-center space-x-3">
              <i class="fas fa-sign-out-alt"></i>
              <span>Sign Out</span>
            </div>
          </button>
        </div>
      </div>
    `)
    document.body.appendChild(modal)
    requestAnimationFrame(() => {
      modal.classList.add('active')
    })
  }
  
  openAppSettings() {
    // Switch to dashboard mode to show app settings
    this.showDashboard()
  }
  
  // Content builders
  buildPlusMenuContent() {
    return `
      <div class="p-6 space-y-4">
        <!-- Camera/Image Upload Section -->
        <div class="grid grid-cols-2 gap-3 mb-4">
          <button onclick="document.getElementById('mobile-camera-input').click()" 
                  class="flex flex-col items-center justify-center p-6 bg-white dark:bg-gray-800 rounded-xl hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors shadow-sm">
            <div class="w-12 h-12 bg-blue-100 dark:bg-blue-900/30 rounded-lg flex items-center justify-center mb-3">
              <i class="fas fa-camera text-blue-600 dark:text-blue-400 text-xl"></i>
            </div>
            <span class="text-sm font-medium text-gray-900 dark:text-white">Camera</span>
          </button>
          
          <button onclick="document.getElementById('mobile-image-input').click()"
                  class="flex flex-col items-center justify-center p-6 bg-white dark:bg-gray-800 rounded-xl hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors shadow-sm">
            <div class="w-12 h-12 bg-green-100 dark:bg-green-900/30 rounded-lg flex items-center justify-center mb-3">
              <i class="fas fa-images text-green-600 dark:text-green-400 text-xl"></i>
            </div>
            <span class="text-sm font-medium text-gray-900 dark:text-white">Images</span>
          </button>
        </div>
        
        <!-- Hidden file inputs -->
        <input type="file" id="mobile-camera-input" accept="image/*" capture="camera" class="hidden" 
               data-action="change->mobile-navigation#handleImageUpload">
        <input type="file" id="mobile-image-input" accept="image/*" class="hidden"
               data-action="change->mobile-navigation#handleImageUpload">
        
        <!-- AI Suggestions -->
        <button data-action="click->mobile-navigation#openAISuggestions"
                class="w-full flex items-center space-x-3 p-4 bg-white dark:bg-gray-800 rounded-xl hover:bg-gray-100 dark:hover:bg-gray-700 transition-all text-left shadow-sm">
          <div class="w-12 h-12 bg-gradient-to-br from-purple-500 to-blue-500 rounded-lg flex items-center justify-center shadow-md">
            <i class="fas fa-sparkles text-white text-xl"></i>
          </div>
          <div>
            <div class="font-medium text-gray-900 dark:text-white">AI Suggestions</div>
            <div class="text-sm text-gray-600 dark:text-gray-400">Get smart ideas for your app</div>
          </div>
        </button>
        
        <!-- Other Actions -->
        <div class="pt-2 space-y-2">
          <button class="w-full flex items-center space-x-3 p-3 bg-white dark:bg-gray-800 hover:bg-gray-100 dark:hover:bg-gray-700 rounded-lg transition-colors text-left">
            <div class="w-8 h-8 flex items-center justify-center">
              <i class="fas fa-plus-circle text-gray-400 dark:text-gray-500 text-lg"></i>
            </div>
            <span class="text-sm text-gray-700 dark:text-gray-300">New Component</span>
          </button>
          
          <button class="w-full flex items-center space-x-3 p-3 bg-white dark:bg-gray-800 hover:bg-gray-100 dark:hover:bg-gray-700 rounded-lg transition-colors text-left">
            <div class="w-8 h-8 flex items-center justify-center">
              <i class="fas fa-file-import text-gray-400 dark:text-gray-500 text-lg"></i>
            </div>
            <span class="text-sm text-gray-700 dark:text-gray-300">Import Code</span>
          </button>
          
          <button class="w-full flex items-center space-x-3 p-3 bg-white dark:bg-gray-800 hover:bg-gray-100 dark:hover:bg-gray-700 rounded-lg transition-colors text-left">
            <div class="w-8 h-8 flex items-center justify-center">
              <i class="fas fa-database text-gray-400 dark:text-gray-500 text-lg"></i>
            </div>
            <span class="text-sm text-gray-700 dark:text-gray-300">Database Action</span>
          </button>
        </div>
      </div>
    `
  }
  
  buildPageSelectorContent() {
    // Get app ID from data attribute - this should be the obfuscated ID
    const appId = this.element.dataset.mobileNavigationAppIdValue
    console.log('App ID for page selector:', appId)
    
    if (!appId) {
      return '<div class="p-4 text-gray-500">No pages found</div>'
    }
    
    // Fetch app files and build the list with proper authentication
    fetch(`/account/apps/${appId}/app_files.json`, {
      method: 'GET',
      headers: {
        'Content-Type': 'application/json',
        'X-Requested-With': 'XMLHttpRequest',
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || ''
      },
      credentials: 'same-origin'
    })
      .then(response => {
        if (!response.ok) {
          throw new Error(`HTTP error! status: ${response.status}`);
        }
        return response.json();
      })
      .then(files => {
        // Filter for HTML files and pages folder
        const htmlFiles = files.filter(file => {
          return file.path.endsWith('.html') || 
                 file.path.includes('/pages/') || 
                 file.file_type === 'html'
        })
        
        if (htmlFiles.length === 0) {
          return '<div class="p-4 text-gray-500">No HTML pages found</div>'
        }
        
        // Build HTML for file list
        const fileListHtml = htmlFiles.map(file => {
          const isActive = this.currentPageFile === file.path
          return `
            <button class="w-full text-left px-4 py-3 hover:bg-gray-50 dark:hover:bg-gray-700 rounded-lg transition-colors"
                    data-action="click->mobile-navigation#selectPage"
                    data-page-path="${file.path}">
              <div class="flex items-center justify-between">
                <div class="flex items-center space-x-2">
                  <i class="fas fa-file-code text-gray-400 text-sm"></i>
                  <span class="text-gray-900 dark:text-white">${file.path}</span>
                </div>
                ${isActive ? '<i class="fas fa-check text-blue-500"></i>' : ''}
              </div>
            </button>
          `
        }).join('')
        
        // Update modal content
        const modal = document.querySelector('.mobile-modal.active')
        if (modal) {
          const contentDiv = modal.querySelector('.flex-1.overflow-y-auto')
          if (contentDiv) {
            contentDiv.innerHTML = `<div class="p-4 space-y-2">${fileListHtml}</div>`
          }
        }
      })
      .catch(error => {
        console.error('Error fetching app files:', error)
        return '<div class="p-4 text-red-500">Error loading pages</div>'
      })
    
    // Return loading state initially
    return '<div class="p-4 text-gray-500">Loading pages...</div>'
  }
  
  buildAISuggestionsContent() {
    return `
      <div class="p-6 space-y-4">
        <p class="text-sm text-gray-600 dark:text-gray-400 mb-4">
          Let AI help improve your app with these suggestions:
        </p>
        
        <div class="space-y-3">
          <button onclick="window.mobileNav.sendAISuggestion('Make my app fully responsive for mobile devices')"
                  class="w-full flex items-start space-x-3 p-4 bg-gray-50 dark:bg-gray-700 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-600 transition-colors text-left">
            <i class="fas fa-mobile-alt text-blue-500 mt-0.5"></i>
            <div>
              <div class="font-medium text-gray-900 dark:text-white">Mobile Optimization</div>
              <div class="text-sm text-gray-600 dark:text-gray-400">Make your app look great on all devices</div>
            </div>
          </button>
          
          <button onclick="window.mobileNav.sendAISuggestion('Add dark mode support to my app')"
                  class="w-full flex items-start space-x-3 p-4 bg-gray-50 dark:bg-gray-700 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-600 transition-colors text-left">
            <i class="fas fa-moon text-purple-500 mt-0.5"></i>
            <div>
              <div class="font-medium text-gray-900 dark:text-white">Dark Mode</div>
              <div class="text-sm text-gray-600 dark:text-gray-400">Add a toggle for dark/light themes</div>
            </div>
          </button>
          
          <button onclick="window.mobileNav.sendAISuggestion('Improve the accessibility of my app')"
                  class="w-full flex items-start space-x-3 p-4 bg-gray-50 dark:bg-gray-700 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-600 transition-colors text-left">
            <i class="fas fa-universal-access text-green-500 mt-0.5"></i>
            <div>
              <div class="font-medium text-gray-900 dark:text-white">Accessibility</div>
              <div class="text-sm text-gray-600 dark:text-gray-400">Make your app usable for everyone</div>
            </div>
          </button>
          
          <button onclick="window.mobileNav.sendAISuggestion('Add animations and transitions to make my app feel more polished')"
                  class="w-full flex items-start space-x-3 p-4 bg-gray-50 dark:bg-gray-700 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-600 transition-colors text-left">
            <i class="fas fa-magic text-orange-500 mt-0.5"></i>
            <div>
              <div class="font-medium text-gray-900 dark:text-white">Polish & Animations</div>
              <div class="text-sm text-gray-600 dark:text-gray-400">Add smooth transitions and effects</div>
            </div>
          </button>
        </div>
      </div>
    `
  }
  
  buildInviteContent() {
    return `
      <div class="p-6 space-y-4">
        <p class="text-sm text-gray-600 dark:text-gray-400">
          Invite team members to collaborate on this app.
        </p>
        
        <div class="space-y-3">
          <div>
            <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
              Email address
            </label>
            <input type="email" 
                   placeholder="colleague@example.com"
                   class="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-lg focus:ring-2 focus:ring-blue-500 dark:bg-gray-700 dark:text-white">
          </div>
          
          <div>
            <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
              Role
            </label>
            <select class="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-lg focus:ring-2 focus:ring-blue-500 dark:bg-gray-700 dark:text-white">
              <option>Viewer</option>
              <option>Editor</option>
              <option>Admin</option>
            </select>
          </div>
          
          <button class="w-full bg-blue-600 hover:bg-blue-700 text-white font-medium py-2 px-4 rounded-lg transition-colors">
            Send Invitation
          </button>
        </div>
        
        <div class="pt-4 border-t border-gray-200 dark:border-gray-700">
          <h4 class="text-sm font-medium text-gray-900 dark:text-white mb-3">Current collaborators</h4>
          <div class="space-y-2">
            <div class="flex items-center justify-between p-2">
              <div class="flex items-center space-x-3">
                <div class="w-8 h-8 rounded-full bg-gray-300 dark:bg-gray-600 flex items-center justify-center">
                  <span class="text-xs font-medium text-gray-600 dark:text-gray-300">Y</span>
                </div>
                <div>
                  <div class="text-sm font-medium text-gray-900 dark:text-white">You</div>
                  <div class="text-xs text-gray-500">Owner</div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    `
  }
}