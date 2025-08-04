import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["list", "item"]
  static values = { appId: String }
  
  connect() {
    // Auto-refresh every 30 seconds
    this.refreshInterval = setInterval(() => {
      this.refresh()
    }, 30000)
  }
  
  disconnect() {
    if (this.refreshInterval) {
      clearInterval(this.refreshInterval)
    }
  }
  
  filterByMethod(event) {
    const selectedMethod = event.target.value
    
    this.itemTargets.forEach(item => {
      const itemMethod = item.dataset.method
      
      if (!selectedMethod || itemMethod === selectedMethod) {
        item.style.display = ''
      } else {
        item.style.display = 'none'
      }
    })
  }
  
  async clearAll() {
    if (!confirm('Are you sure you want to clear all API call logs? This cannot be undone.')) {
      return
    }
    
    try {
      const response = await fetch(`/account/apps/${this.appIdValue}/api_calls`, {
        method: 'DELETE',
        headers: {
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
          'Content-Type': 'application/json'
        }
      })
      
      if (response.ok) {
        // Refresh the activity monitor
        this.refresh()
      } else {
        console.error('Failed to clear API calls')
      }
    } catch (error) {
      console.error('Error clearing API calls:', error)
    }
  }
  
  async refresh() {
    try {
      const response = await fetch(`/account/apps/${this.appIdValue}/editor/activity_monitor`, {
        headers: {
          'Accept': 'text/html',
          'X-Requested-With': 'XMLHttpRequest'
        }
      })
      
      if (response.ok) {
        const html = await response.text()
        // Replace the entire activity monitor content
        this.element.outerHTML = html
      }
    } catch (error) {
      console.error('Error refreshing activity monitor:', error)
      // Show refresh icon spinning briefly to indicate attempt
      const refreshButton = this.element.querySelector('[data-action*="refresh"]')
      if (refreshButton) {
        const icon = refreshButton.querySelector('i')
        if (icon) {
          icon.classList.add('fa-spin')
          setTimeout(() => {
            icon.classList.remove('fa-spin')
          }, 1000)
        }
      }
    }
  }
  
  showDetails(event) {
    const callId = event.currentTarget.dataset.callId
    
    // Create modal to show API call details
    this.showApiCallDetails(callId)
  }
  
  async showApiCallDetails(callId) {
    try {
      const response = await fetch(`/account/apps/${this.appIdValue}/api_calls/${callId}`, {
        headers: {
          'Accept': 'application/json',
          'X-Requested-With': 'XMLHttpRequest'
        }
      })
      
      if (response.ok) {
        const apiCall = await response.json()
        this.displayApiCallModal(apiCall)
      }
    } catch (error) {
      console.error('Error fetching API call details:', error)
    }
  }
  
  displayApiCallModal(apiCall) {
    // Create modal HTML
    const modal = document.createElement('div')
    modal.className = 'fixed inset-0 bg-black bg-opacity-50 z-50 flex items-center justify-center p-4'
    modal.innerHTML = `
      <div class="bg-white dark:bg-gray-800 rounded-lg max-w-4xl w-full max-h-[90vh] overflow-y-auto">
        <div class="sticky top-0 bg-white dark:bg-gray-800 px-6 py-4 border-b border-gray-200 dark:border-gray-700 flex items-center justify-between">
          <h3 class="text-lg font-semibold text-gray-900 dark:text-white">API Call Details</h3>
          <button class="text-gray-400 hover:text-gray-600 dark:hover:text-gray-300" onclick="this.closest('.fixed').remove()">
            <i class="fas fa-times"></i>
          </button>
        </div>
        
        <div class="p-6 space-y-6">
          <!-- Request Info -->
          <div>
            <h4 class="text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">Request</h4>
            <div class="bg-gray-50 dark:bg-gray-900 rounded-lg p-4 space-y-2">
              <div class="flex items-center space-x-4">
                <span class="text-xs font-mono font-semibold px-2 py-1 rounded ${this.getMethodColor(apiCall.http_method)}">${apiCall.http_method}</span>
                <span class="font-mono text-sm">${apiCall.path}</span>
              </div>
              <div class="text-xs text-gray-500 dark:text-gray-400">
                ${apiCall.occurred_at} • ${apiCall.ip_address || 'Unknown IP'}
              </div>
              ${apiCall.user_agent ? `<div class="text-xs text-gray-500 dark:text-gray-400">User-Agent: ${apiCall.user_agent}</div>` : ''}
            </div>
          </div>
          
          <!-- Response Info -->
          <div>
            <h4 class="text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">Response</h4>
            <div class="bg-gray-50 dark:bg-gray-900 rounded-lg p-4 space-y-2">
              <div class="flex items-center space-x-4">
                <span class="text-xs font-medium ${this.getStatusColor(apiCall.status_code)} flex items-center">
                  <i class="${this.getStatusIcon(apiCall.status_code)} mr-1"></i>
                  ${apiCall.status_code}
                </span>
                ${apiCall.response_time ? `<span class="text-xs text-gray-500 dark:text-gray-400">${apiCall.response_time}ms</span>` : ''}
              </div>
            </div>
          </div>
          
          ${apiCall.request_body ? `
          <div>
            <h4 class="text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">Request Body</h4>
            <pre class="bg-gray-50 dark:bg-gray-900 rounded-lg p-4 text-xs overflow-x-auto"><code>${this.formatJson(apiCall.request_body)}</code></pre>
          </div>
          ` : ''}
          
          ${apiCall.response_body ? `
          <div>
            <h4 class="text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">Response Body</h4>
            <pre class="bg-gray-50 dark:bg-gray-900 rounded-lg p-4 text-xs overflow-x-auto"><code>${this.formatJson(apiCall.response_body)}</code></pre>
          </div>
          ` : ''}
        </div>
      </div>
    `
    
    document.body.appendChild(modal)
    
    // Close on backdrop click
    modal.addEventListener('click', (e) => {
      if (e.target === modal) {
        modal.remove()
      }
    })
  }
  
  getMethodColor(method) {
    switch (method) {
      case 'GET': return 'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200'
      case 'POST': return 'bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200'
      case 'PUT': return 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200'
      case 'DELETE': return 'bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200'
      default: return 'bg-gray-100 text-gray-800 dark:bg-gray-900 dark:text-gray-200'
    }
  }
  
  getStatusColor(status) {
    if (status >= 200 && status < 300) return 'text-green-600 dark:text-green-400'
    if (status >= 300 && status < 400) return 'text-blue-600 dark:text-blue-400'
    if (status >= 400 && status < 500) return 'text-yellow-600 dark:text-yellow-400'
    if (status >= 500) return 'text-red-600 dark:text-red-400'
    return 'text-gray-600 dark:text-gray-400'
  }
  
  getStatusIcon(status) {
    if (status >= 200 && status < 300) return 'fas fa-check-circle'
    if (status >= 300 && status < 400) return 'fas fa-arrow-right'
    if (status >= 400 && status < 500) return 'fas fa-exclamation-triangle'
    if (status >= 500) return 'fas fa-times-circle'
    return 'fas fa-question-circle'
  }
  
  formatJson(jsonString) {
    try {
      const parsed = JSON.parse(jsonString)
      return JSON.stringify(parsed, null, 2)
    } catch (error) {
      return jsonString
    }
  }
  
  async loadMore() {
    // This would implement pagination
    console.log('Load more not implemented yet')
  }
}