import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["preview"]
  static values = { appId: Number }
  
  connect() {
    this.setupErrorDetection()
  }

  setupErrorDetection() {
    // Check if preview target exists before trying to use it
    if (!this.hasPreviewTarget) {
      console.log('Error detector: No preview target found, skipping setup')
      return
    }
    
    const previewFrame = this.previewTarget
    
    if (previewFrame && previewFrame.contentWindow) {
      // Listen for errors in the preview iframe
      previewFrame.contentWindow.addEventListener('error', (event) => {
        this.handleError(event.error, event.filename, event.lineno, event.colno)
      })
      
      // Listen for unhandled promise rejections
      previewFrame.contentWindow.addEventListener('unhandledrejection', (event) => {
        this.handleError(event.reason, 'Promise rejection', 0, 0)
      })
      
      // Override console.error to catch React errors
      if (previewFrame.contentWindow.console) {
        const originalError = previewFrame.contentWindow.console.error
        previewFrame.contentWindow.console.error = (...args) => {
          this.handleConsoleError(args)
          originalError.apply(previewFrame.contentWindow.console, args)
        }
      }
    }
  }

  handleError(error, filename, lineno, colno) {
    const errorInfo = {
      message: error.message || error.toString(),
      filename: filename,
      line: lineno,
      column: colno,
      stack: error.stack,
      timestamp: new Date().toISOString()
    }
    
    // Check if it's a React/JS error that needs debugging
    if (this.shouldAutoDebug(errorInfo)) {
      this.triggerAutoDebug(errorInfo)
    }
  }

  handleConsoleError(args) {
    const errorMessage = args.join(' ')
    
    // Check for common React errors
    const reactErrorPatterns = [
      /is not defined/,
      /Cannot read propert(y|ies) of undefined/,
      /Cannot read propert(y|ies) of null/,
      /Unexpected token/,
      /SyntaxError/,
      /ReferenceError/,
      /TypeError/
    ]
    
    const isReactError = reactErrorPatterns.some(pattern => pattern.test(errorMessage))
    
    if (isReactError) {
      const errorInfo = {
        message: errorMessage,
        type: 'console',
        timestamp: new Date().toISOString()
      }
      
      this.triggerAutoDebug(errorInfo)
    }
  }

  shouldAutoDebug(errorInfo) {
    // Auto-debug for common development errors
    const autoDebugPatterns = [
      /is not defined/,
      /Cannot read propert/,
      /Unexpected token/,
      /SyntaxError/,
      /ReferenceError/,
      /Import.*not found/,
      /Module.*not found/
    ]
    
    return autoDebugPatterns.some(pattern => pattern.test(errorInfo.message))
  }

  async triggerAutoDebug(errorInfo) {
    // Show debugging indicator to user
    this.showDebuggingIndicator()
    
    try {
      // Send error to AI for debugging
      const response = await fetch(`/account/apps/${this.appIdValue}/debug_error`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        },
        body: JSON.stringify({
          error: errorInfo,
          auto_debug: true
        })
      })
      
      if (response.ok) {
        const result = await response.json()
        this.showDebuggingSuccess(result.message)
      } else {
        this.showDebuggingError()
      }
    } catch (error) {
      console.error('Failed to trigger auto-debug:', error)
      this.showDebuggingError()
    }
  }

  showDebuggingIndicator() {
    // Create or update debugging notification
    let indicator = document.getElementById('debugging-indicator')
    
    if (!indicator) {
      indicator = document.createElement('div')
      indicator.id = 'debugging-indicator'
      indicator.className = 'fixed top-4 right-4 bg-yellow-500 text-white px-4 py-2 rounded-lg shadow-lg z-50 flex items-center space-x-2'
      document.body.appendChild(indicator)
    }
    
    indicator.innerHTML = `
      <div class="animate-spin rounded-full h-4 w-4 border-2 border-white border-t-transparent"></div>
      <span class="text-sm font-medium">🔧 AI is debugging your app...</span>
    `
  }

  showDebuggingSuccess(message) {
    const indicator = document.getElementById('debugging-indicator')
    if (indicator) {
      indicator.className = 'fixed top-4 right-4 bg-green-500 text-white px-4 py-2 rounded-lg shadow-lg z-50 flex items-center space-x-2'
      indicator.innerHTML = `
        <i class="fas fa-check-circle"></i>
        <span class="text-sm font-medium">✅ ${message || 'Error fixed! Refreshing preview...'}</span>
      `
      
      // Auto-hide after 3 seconds
      setTimeout(() => {
        if (indicator) indicator.remove()
      }, 3000)
    }
  }

  showDebuggingError() {
    const indicator = document.getElementById('debugging-indicator')
    if (indicator) {
      indicator.className = 'fixed top-4 right-4 bg-red-500 text-white px-4 py-2 rounded-lg shadow-lg z-50 flex items-center space-x-2'
      indicator.innerHTML = `
        <i class="fas fa-exclamation-triangle"></i>
        <span class="text-sm font-medium">❌ Auto-debug failed. Try asking AI for help.</span>
      `
      
      // Auto-hide after 5 seconds
      setTimeout(() => {
        if (indicator) indicator.remove()
      }, 5000)
    }
  }
}