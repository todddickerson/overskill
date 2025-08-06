import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="version-progress"
export default class extends Controller {
  static targets = [
    "statusIndicator", "versionTitle", "timestamp", "progressSummary",
    "completedCount", "totalCount", "fileList", "versionActions", 
    "finalVersion", "fileItem"
  ]
  
  static values = {
    messageId: String,
    versionId: String
  }

  connect() {
    console.log("Version progress controller connected for message", this.messageIdValue)
    this.files = new Map() // Track file states
    this.setupEventListeners()
  }

  setupEventListeners() {
    // Listen for version progress updates via custom events
    document.addEventListener(`version:progress:${this.messageIdValue}`, (event) => {
      this.handleProgressUpdate(event.detail)
    })
    
    document.addEventListener(`version:file:${this.messageIdValue}`, (event) => {
      this.handleFileUpdate(event.detail)
    })
    
    document.addEventListener(`version:complete:${this.messageIdValue}`, (event) => {
      this.handleVersionComplete(event.detail)
    })
  }

  handleProgressUpdate(data) {
    // Update overall progress
    if (data.status) {
      this.updateStatusIndicator(data.status)
    }
    
    if (data.title) {
      this.versionTitleTarget.textContent = data.title
    }
    
    this.updateProgressCounts()
  }

  handleFileUpdate(data) {
    const { file_path, status, lines_changed } = data
    
    // Update or create file item
    if (!this.files.has(file_path)) {
      this.addFileItem(file_path, status, lines_changed)
    } else {
      this.updateFileItem(file_path, status, lines_changed)
    }
    
    this.files.set(file_path, { status, lines_changed })
    this.updateProgressCounts()
  }

  handleVersionComplete(data) {
    const { version_id, version_number, display_name } = data
    
    // Update to completed state
    this.updateStatusIndicator('completed')
    this.versionTitleTarget.textContent = display_name || `Version ${version_number} Created`
    
    // Show action buttons
    this.finalVersionTarget.textContent = version_number
    this.versionActionsTarget.classList.remove('hidden')
    
    // Store version ID for actions
    this.versionIdValue = version_id
    this.updateActionButtons(version_id)
    
    // Update card styling to completed state
    this.element.className = this.element.className.replace(
      /from-blue-50 to-indigo-50.*?border-blue-200/,
      'from-green-50 to-emerald-50 dark:from-green-900/20 dark:to-emerald-900/20 border border-green-200 dark:border-green-700'
    )
    
    // Re-enable chat form
    this.enableChatForm()
    
    // Trigger preview deployment
    this.triggerPreviewDeployment(version_id)
  }

  addFileItem(filePath, status, linesChanged = null) {
    // Create file item HTML
    const fileItem = document.createElement('div')
    fileItem.innerHTML = this.generateFileItemHTML(filePath, status, linesChanged)
    fileItem.dataset.filePath = filePath
    fileItem.dataset.versionProgressTarget = "fileItem"
    
    this.fileListTarget.appendChild(fileItem.firstElementChild)
  }

  updateFileItem(filePath, status, linesChanged = null) {
    const fileItem = this.fileListTarget.querySelector(`[data-file-path="${filePath}"]`)
    if (fileItem) {
      fileItem.innerHTML = this.generateFileItemHTML(filePath, status, linesChanged).replace(/^<div[^>]*>|<\/div>$/g, '')
    }
  }

  generateFileItemHTML(filePath, status, linesChanged) {
    const fileName = filePath.split('/').pop()
    const fileDir = filePath.includes('/') ? filePath.split('/').slice(0, -1).join('/') : null
    
    let statusIcon = ''
    let statusText = ''
    let statusColor = ''
    
    switch (status) {
      case 'pending':
        statusIcon = '<div class="w-4 h-4 rounded-full border-2 border-gray-300 dark:border-gray-600"></div>'
        statusText = 'Queued'
        statusColor = 'text-gray-500 dark:text-gray-400'
        break
      case 'editing':
        statusIcon = '<div class="w-4 h-4 rounded-full border-2 border-blue-500 border-t-transparent animate-spin"></div>'
        statusText = 'Editing...'
        statusColor = 'text-blue-600 dark:text-blue-400 font-medium'
        break
      case 'completed':
        statusIcon = '<div class="w-4 h-4 rounded-full bg-green-500 flex items-center justify-center"><i class="fas fa-check text-white text-xs"></i></div>'
        statusText = linesChanged ? `+${linesChanged} lines` : 'Updated'
        statusColor = 'text-green-600 dark:text-green-400 font-medium'
        break
      case 'error':
        statusIcon = '<div class="w-4 h-4 rounded-full bg-red-500 flex items-center justify-center"><i class="fas fa-times text-white text-xs"></i></div>'
        statusText = 'Failed'
        statusColor = 'text-red-600 dark:text-red-400 font-medium'
        break
    }
    
    return `
      <div class="flex items-center justify-between py-2 px-3 bg-white/50 dark:bg-gray-800/50 rounded-lg border border-gray-200/50 dark:border-gray-600/50">
        <div class="flex items-center space-x-3">
          <div class="flex-shrink-0">${statusIcon}</div>
          <div class="flex items-center space-x-2">
            <i class="fas fa-file text-gray-400 text-sm"></i>
            <button 
              class="text-sm font-medium text-blue-600 dark:text-blue-400 hover:text-blue-800 dark:hover:text-blue-300 underline-offset-2 hover:underline"
              data-action="click->file-tree#navigateToFile"
              data-file-path="${filePath}"
              title="Open ${filePath} in code editor">
              ${fileName}
            </button>
            ${fileDir ? `<span class="text-xs text-gray-500 dark:text-gray-400">in ${fileDir}</span>` : ''}
          </div>
        </div>
        <div class="text-xs ${statusColor}">${statusText}</div>
      </div>
    `
  }

  updateStatusIndicator(status) {
    const indicator = this.statusIndicatorTarget
    
    switch (status) {
      case 'editing':
        indicator.className = 'w-2 h-2 bg-blue-500 rounded-full animate-pulse'
        break
      case 'completed':
        indicator.className = 'w-2 h-2 bg-green-500 rounded-full'
        break
      case 'error':
        indicator.className = 'w-2 h-2 bg-red-500 rounded-full'
        break
    }
  }

  updateProgressCounts() {
    const completed = Array.from(this.files.values()).filter(f => f.status === 'completed').length
    const total = this.files.size
    
    this.completedCountTarget.textContent = completed
    this.totalCountTarget.textContent = total
  }

  updateActionButtons(versionId) {
    // Update all action buttons with the version ID
    this.versionActionsTarget.querySelectorAll('[data-version-progress-version-id-param]').forEach(button => {
      button.dataset.versionProgressVersionIdParam = versionId
    })
  }

  // Helper methods
  enableChatForm() {
    // Re-enable the chat form by removing disabled state and showing it
    const chatForm = document.querySelector('#chat_form')
    const chatInput = document.querySelector('#chat_input')
    
    if (chatForm) {
      chatForm.style.display = 'block'
      chatForm.classList.remove('opacity-50', 'pointer-events-none')
    }
    
    if (chatInput) {
      chatInput.disabled = false
      chatInput.placeholder = "Ask me to modify your app..."
    }
    
    // Re-enable submit button
    const submitButton = document.querySelector('#chat_submit_button')
    if (submitButton) {
      submitButton.disabled = false
      submitButton.classList.remove('opacity-50', 'cursor-not-allowed')
    }
  }

  triggerPreviewDeployment(versionId) {
    // Trigger preview deployment via fetch to update_preview endpoint
    const appId = this.getAppIdFromUrl()
    if (appId) {
      fetch(`/account/apps/${appId}/update_preview`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
        },
        body: JSON.stringify({ version_id: versionId })
      }).catch(error => {
        console.warn('Preview deployment failed:', error)
      })
    }
  }

  getAppIdFromUrl() {
    const pathParts = window.location.pathname.split('/')
    const appIndex = pathParts.indexOf('apps')
    return appIndex !== -1 && pathParts[appIndex + 1] ? pathParts[appIndex + 1] : null
  }

  // Action methods
  preview(event) {
    const versionId = event.currentTarget.dataset.versionProgressVersionIdParam
    
    // Switch to preview tab and load this version
    const previewTab = document.querySelector('[data-main-tabs-target="tab"][data-tab="preview"]')
    if (previewTab) {
      previewTab.click()
      
      // Wait for tab to load then set version
      setTimeout(() => {
        const previewFrame = document.querySelector('#preview_frame')
        if (previewFrame && versionId) {
          const appId = this.getAppIdFromUrl()
          previewFrame.src = `/account/apps/${appId}/preview?version=${versionId}`
        }
      }, 100)
    }
  }

  compare(event) {
    const versionId = event.currentTarget.dataset.versionProgressVersionIdParam
    
    // Open version comparison modal or side panel
    const appId = this.getAppIdFromUrl()
    const compareUrl = `/account/apps/${appId}/versions/${versionId}/compare`
    
    // For now, open in a new tab - could be enhanced with modal
    window.open(compareUrl, '_blank')
  }

  restore(event) {
    const versionId = event.currentTarget.dataset.versionProgressVersionIdParam
    
    if (confirm('Are you sure you want to restore to this version? This will replace your current files.')) {
      const appId = this.getAppIdFromUrl()
      
      fetch(`/account/apps/${appId}/versions/${versionId}/restore`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
        }
      })
      .then(response => response.json())
      .then(data => {
        if (data.success) {
          // Refresh the page to show restored files
          window.location.reload()
        } else {
          alert('Failed to restore version: ' + (data.error || 'Unknown error'))
        }
      })
      .catch(error => {
        console.error('Restore failed:', error)
        alert('Failed to restore version. Please try again.')
      })
    }
  }

  bookmark(event) {
    const versionId = event.currentTarget.dataset.versionProgressVersionIdParam
    const button = event.currentTarget
    const icon = button.querySelector('i')
    
    const appId = this.getAppIdFromUrl()
    
    fetch(`/account/apps/${appId}/versions/${versionId}/bookmark`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
      }
    })
    .then(response => response.json())
    .then(data => {
      if (data.success) {
        // Update button appearance
        if (data.bookmarked) {
          icon.classList.add('text-yellow-500')
          button.title = 'Remove bookmark'
        } else {
          icon.classList.remove('text-yellow-500')
          button.title = 'Bookmark this version'
        }
      }
    })
    .catch(error => {
      console.error('Bookmark failed:', error)
    })
  }
}