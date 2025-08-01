import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal", "content", "loading", "versionA", "versionB", "diffContainer"]
  static values = { 
    appId: String,
    versionId: String 
  }
  
  connect() {
    // Listen for version comparison requests
    window.addEventListener('message', this.handleVersionComparison.bind(this))
  }
  
  disconnect() {
    window.removeEventListener('message', this.handleVersionComparison.bind(this))
  }
  
  handleVersionComparison(event) {
    if (event.data.action === 'compare' && event.data.version) {
      this.compareVersion(event.data.version)
    }
  }
  
  async compareVersion(versionId) {
    this.versionIdValue = versionId
    this.open()
    this.showLoading()
    
    try {
      // Get version comparison data
      const response = await fetch(`/account/app_versions/${versionId}/compare`)
      if (response.ok) {
        const data = await response.json()
        this.displayComparison(data)
      } else {
        this.showError("Failed to load version comparison")
      }
    } catch (error) {
      console.error("Failed to load comparison:", error)
      this.showError("Error loading version comparison")
    }
  }
  
  displayComparison(data) {
    this.hideLoading()
    
    // Update version labels
    if (this.hasVersionATarget) {
      this.versionATarget.textContent = data.previous_version || "Previous"
    }
    if (this.hasVersionBTarget) {
      this.versionBTarget.textContent = data.current_version || "Current"
    }
    
    // Generate diff HTML
    const diffHtml = this.generateDiffHtml(data.file_changes)
    this.diffContainerTarget.innerHTML = diffHtml
  }
  
  generateDiffHtml(fileChanges) {
    if (!fileChanges || fileChanges.length === 0) {
      return '<div class="text-center py-8 text-gray-500 dark:text-gray-400">No changes found in this version</div>'
    }
    
    let html = '<div class="space-y-6">'
    
    fileChanges.forEach(change => {
      html += `
        <div class="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 overflow-hidden">
          <div class="flex items-center justify-between px-4 py-3 bg-gray-50 dark:bg-gray-700 border-b border-gray-200 dark:border-gray-600">
            <div class="flex items-center space-x-3">
              <div class="w-3 h-3 rounded-full ${this.getStatusColor(change.status)}"></div>
              <span class="font-mono text-sm font-medium text-gray-900 dark:text-gray-100">${change.path}</span>
              <span class="text-xs px-2 py-1 rounded-full ${this.getStatusBadgeColor(change.status)}">${change.status}</span>
            </div>
            <div class="text-xs text-gray-500 dark:text-gray-400">
              ${change.additions ? `+${change.additions}` : ''} ${change.deletions ? `-${change.deletions}` : ''}
            </div>
          </div>
          <div class="overflow-x-auto">
            <pre class="text-xs leading-relaxed">${this.formatDiff(change.diff)}</pre>
          </div>
        </div>
      `
    })
    
    html += '</div>'
    return html
  }
  
  formatDiff(diff) {
    if (!diff) return '<div class="p-4 text-gray-500 dark:text-gray-400 text-center">No diff available</div>'
    
    return diff.split('\n').map(line => {
      const escapedLine = this.escapeHtml(line)
      
      if (line.startsWith('+')) {
        return `<div class="bg-green-50 dark:bg-green-900/20 text-green-800 dark:text-green-200 px-4 py-1">${escapedLine}</div>`
      } else if (line.startsWith('-')) {
        return `<div class="bg-red-50 dark:bg-red-900/20 text-red-800 dark:text-red-200 px-4 py-1">${escapedLine}</div>`
      } else if (line.startsWith('@@')) {
        return `<div class="bg-blue-50 dark:bg-blue-900/20 text-blue-800 dark:text-blue-200 px-4 py-1 font-medium">${escapedLine}</div>`
      } else {
        return `<div class="text-gray-700 dark:text-gray-300 px-4 py-1">${escapedLine}</div>`
      }
    }).join('')
  }
  
  getStatusColor(status) {
    switch (status) {
      case 'created': return 'bg-green-500'
      case 'updated': return 'bg-yellow-500'
      case 'deleted': return 'bg-red-500'
      default: return 'bg-gray-500'
    }
  }
  
  getStatusBadgeColor(status) {
    switch (status) {
      case 'created': return 'bg-green-100 dark:bg-green-900/30 text-green-800 dark:text-green-300'
      case 'updated': return 'bg-yellow-100 dark:bg-yellow-900/30 text-yellow-800 dark:text-yellow-300'
      case 'deleted': return 'bg-red-100 dark:bg-red-900/30 text-red-800 dark:text-red-300'
      default: return 'bg-gray-100 dark:bg-gray-700 text-gray-800 dark:text-gray-300'
    }
  }
  
  escapeHtml(text) {
    const div = document.createElement('div')
    div.textContent = text
    return div.innerHTML
  }
  
  showLoading() {
    if (this.hasLoadingTarget) {
      this.loadingTarget.classList.remove('hidden')
    }
    if (this.hasContentTarget) {
      this.contentTarget.classList.add('hidden')
    }
  }
  
  hideLoading() {
    if (this.hasLoadingTarget) {
      this.loadingTarget.classList.add('hidden')
    }
    if (this.hasContentTarget) {
      this.contentTarget.classList.remove('hidden')
    }
  }
  
  showError(message) {
    this.hideLoading()
    if (this.hasDiffContainerTarget) {
      this.diffContainerTarget.innerHTML = `
        <div class="text-center py-8">
          <div class="text-red-500 dark:text-red-400 mb-2">
            <i class="fas fa-exclamation-triangle text-2xl"></i>
          </div>
          <p class="text-gray-600 dark:text-gray-400">${message}</p>
        </div>
      `
    }
    if (this.hasContentTarget) {
      this.contentTarget.classList.remove('hidden')
    }
  }
  
  open() {
    if (this.hasModalTarget) {
      this.modalTarget.classList.remove('hidden')
      document.body.style.overflow = 'hidden'
    }
  }
  
  close(event) {
    if (event) event.preventDefault()
    if (this.hasModalTarget) {
      this.modalTarget.classList.add('hidden')
      document.body.style.overflow = ''
    }
  }
  
  closeOnBackdrop(event) {
    if (event.target === this.modalTarget) {
      this.close()
    }
  }
}