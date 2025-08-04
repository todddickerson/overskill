import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "baseUrl", "endpointsList", "requestPanel", "responsePanel", "responseInfo",
    "methodSelect", "urlInput", "bodyInput", "headersList", "tabContent", "tab"
  ]
  static values = { appId: Number }
  
  connect() {
    this.headers = [
      { name: 'Content-Type', value: 'application/json' }
    ]
    this.authToken = null
  }
  
  selectEndpoint(event) {
    const button = event.currentTarget
    const method = button.dataset.method
    const path = button.dataset.path
    const description = button.dataset.description
    
    // Update method and URL
    this.methodSelectTarget.value = method
    this.urlInputTarget.value = path
    
    // Switch to body tab for POST/PUT
    if (['POST', 'PUT', 'PATCH'].includes(method)) {
      this.switchToTab('body')
      
      // Add sample body based on endpoint
      if (path.includes('auth/login')) {
        this.bodyInputTarget.value = JSON.stringify({
          email: "user@example.com",
          password: "password"
        }, null, 2)
      } else if (path.includes('auth/signup')) {
        this.bodyInputTarget.value = JSON.stringify({
          email: "user@example.com",
          password: "password",
          name: "John Doe"
        }, null, 2)
      } else if (method === 'POST') {
        // Generic create body
        this.bodyInputTarget.value = JSON.stringify({
          // Add fields based on table
        }, null, 2)
      }
    }
    
    // Highlight selected endpoint
    const allButtons = this.endpointsListTarget.querySelectorAll('button')
    allButtons.forEach(btn => btn.classList.remove('bg-blue-50', 'dark:bg-blue-900/20'))
    button.classList.add('bg-blue-50', 'dark:bg-blue-900/20')
  }
  
  async sendRequest() {
    const method = this.methodSelectTarget.value
    const path = this.urlInputTarget.value
    const baseUrl = this.baseUrlTarget.value
    
    // Build full URL
    let url = baseUrl + path
    
    // Replace :id with actual ID if present
    if (url.includes(':id')) {
      const id = prompt('Enter the ID:')
      if (!id) return
      url = url.replace(':id', id)
    }
    
    // Build headers
    const headers = {}
    this.headers.forEach(h => {
      if (h.name && h.value) {
        headers[h.name] = h.value
      }
    })
    
    // Add auth if configured
    if (this.authToken) {
      headers['Authorization'] = `Bearer ${this.authToken}`
    }
    
    // Build request options
    const options = {
      method: method,
      headers: headers
    }
    
    // Add body for non-GET requests
    if (['POST', 'PUT', 'PATCH'].includes(method) && this.hasBodyInputTarget) {
      const bodyText = this.bodyInputTarget.value.trim()
      if (bodyText) {
        options.body = bodyText
      }
    }
    
    // Show loading state
    this.responseInfoTarget.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Sending...'
    this.responsePanelTarget.innerHTML = `
      <div class="bg-gray-100 dark:bg-gray-800 rounded-lg p-8 text-center">
        <i class="fas fa-spinner fa-spin text-4xl text-gray-400 mb-3"></i>
        <p class="text-gray-600 dark:text-gray-400">Sending request...</p>
      </div>
    `
    
    const startTime = Date.now()
    
    try {
      const response = await fetch(url, options)
      const duration = Date.now() - startTime
      
      // Update response info
      const statusClass = response.ok ? 'text-green-600' : 'text-red-600'
      this.responseInfoTarget.innerHTML = `
        <span class="${statusClass} font-medium">${response.status} ${response.statusText}</span>
        <span class="text-gray-500">${duration}ms</span>
        <span class="text-gray-500">${this.formatBytes(response.headers.get('content-length'))}</span>
      `
      
      // Get response body
      const contentType = response.headers.get('content-type')
      let responseBody
      
      if (contentType && contentType.includes('application/json')) {
        responseBody = await response.json()
        this.displayJsonResponse(responseBody)
      } else {
        responseBody = await response.text()
        this.displayTextResponse(responseBody)
      }
      
      // Save to history (optional)
      this.saveToHistory({
        method, url, headers, body: options.body,
        response: { status: response.status, body: responseBody },
        duration
      })
      
    } catch (error) {
      const duration = Date.now() - startTime
      
      this.responseInfoTarget.innerHTML = `
        <span class="text-red-600 font-medium">Error</span>
        <span class="text-gray-500">${duration}ms</span>
      `
      
      this.responsePanelTarget.innerHTML = `
        <div class="bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg p-6">
          <h4 class="text-red-800 dark:text-red-200 font-medium mb-2">Request Failed</h4>
          <p class="text-red-700 dark:text-red-300">${error.message}</p>
        </div>
      `
    }
  }
  
  displayJsonResponse(data) {
    this.responsePanelTarget.innerHTML = `
      <div class="bg-gray-900 rounded-lg p-4 overflow-x-auto">
        <pre class="text-sm text-gray-300"><code>${JSON.stringify(data, null, 2)}</code></pre>
      </div>
    `
    
    // Syntax highlighting (optional - could use a library like Prism)
    this.highlightJson()
  }
  
  displayTextResponse(text) {
    this.responsePanelTarget.innerHTML = `
      <div class="bg-gray-100 dark:bg-gray-800 rounded-lg p-4">
        <pre class="text-sm text-gray-700 dark:text-gray-300 whitespace-pre-wrap">${this.escapeHtml(text)}</pre>
      </div>
    `
  }
  
  switchTab(event) {
    const tabName = event.currentTarget.dataset.tab || event
    
    // Update active tab
    this.tabTargets.forEach(tab => {
      if (tab.dataset.tab === tabName) {
        tab.classList.add('border-blue-500', 'text-blue-600', 'dark:text-blue-400')
        tab.classList.remove('border-transparent', 'text-gray-500')
      } else {
        tab.classList.remove('border-blue-500', 'text-blue-600', 'dark:text-blue-400')
        tab.classList.add('border-transparent', 'text-gray-500')
      }
    })
    
    // Show/hide panels
    this.tabContentTarget.querySelectorAll('[data-tab-panel]').forEach(panel => {
      if (panel.dataset.tabPanel === tabName) {
        panel.classList.remove('hidden')
      } else {
        panel.classList.add('hidden')
      }
    })
  }
  
  switchToTab(tabName) {
    this.switchTab(tabName)
  }
  
  addHeader() {
    const headerRow = document.createElement('div')
    headerRow.className = 'flex items-center space-x-3'
    headerRow.innerHTML = `
      <input type="text" placeholder="Header name"
             class="flex-1 px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-gray-900 dark:text-white">
      <input type="text" placeholder="Header value"
             class="flex-1 px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-gray-900 dark:text-white">
      <button class="text-gray-400 hover:text-gray-600 dark:hover:text-gray-300"
              data-action="click->api-explorer#removeHeader">
        <i class="fas fa-times"></i>
      </button>
    `
    
    this.headersListTarget.appendChild(headerRow)
  }
  
  removeHeader(event) {
    event.currentTarget.closest('.flex').remove()
  }
  
  formatBytes(bytes) {
    if (!bytes) return ''
    const kb = bytes / 1024
    return kb > 1024 ? `${(kb / 1024).toFixed(2)} MB` : `${kb.toFixed(2)} KB`
  }
  
  escapeHtml(text) {
    const div = document.createElement('div')
    div.textContent = text
    return div.innerHTML
  }
  
  highlightJson() {
    // Simple JSON syntax highlighting
    const pre = this.responsePanelTarget.querySelector('pre')
    if (!pre) return
    
    let html = pre.innerHTML
    
    // Highlight strings
    html = html.replace(/"([^"]+)":/g, '<span class="text-blue-400">"$1"</span>:')
    html = html.replace(/: "([^"]+)"/g, ': <span class="text-green-400">"$1"</span>')
    
    // Highlight numbers
    html = html.replace(/: (\d+)/g, ': <span class="text-yellow-400">$1</span>')
    
    // Highlight booleans and null
    html = html.replace(/: (true|false|null)/g, ': <span class="text-purple-400">$1</span>')
    
    pre.innerHTML = html
  }
  
  saveToHistory(request) {
    // Could save to localStorage or send to backend
    console.log('Request saved to history:', request)
  }
}