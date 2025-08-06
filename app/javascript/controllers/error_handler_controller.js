import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    console.log("[ErrorHandler] Installing global error handlers")
    
    // Prevent page from going blank on errors
    window.addEventListener('error', this.handleError.bind(this))
    window.addEventListener('unhandledrejection', this.handleRejection.bind(this))
    
    // Override document.write to prevent issues
    this.overrideDocumentWrite()
    
    // Add page visibility handler
    this.handleVisibilityChange()
  }
  
  disconnect() {
    window.removeEventListener('error', this.handleError.bind(this))
    window.removeEventListener('unhandledrejection', this.handleRejection.bind(this))
  }
  
  handleError(event) {
    const error = event.error || event
    
    // Ignore extension errors
    if (error.message && error.message.includes('chrome-extension://')) {
      console.warn('[ErrorHandler] Ignoring Chrome extension error:', error.message)
      event.preventDefault()
      return
    }
    
    // Ignore document.write warnings
    if (error.message && error.message.includes('document.write')) {
      console.warn('[ErrorHandler] Ignoring document.write warning')
      event.preventDefault()
      return
    }
    
    // Ignore third-party script errors
    if (error.filename && (
      error.filename.includes('chrome-extension://') ||
      error.filename.includes('unpkg.com') ||
      error.filename.includes('includes.js')
    )) {
      console.warn('[ErrorHandler] Ignoring third-party error from:', error.filename)
      event.preventDefault()
      return
    }
    
    // Log but don't crash on other errors
    console.error('[ErrorHandler] Caught error:', error)
    
    // Prevent page from going blank
    if (document.body && document.body.innerHTML === '') {
      console.error('[ErrorHandler] Page went blank! Attempting recovery...')
      this.recoverPage()
    }
  }
  
  handleRejection(event) {
    const reason = event.reason
    
    // Ignore extension rejections
    if (reason && reason.toString().includes('chrome-extension://')) {
      console.warn('[ErrorHandler] Ignoring Chrome extension rejection')
      event.preventDefault()
      return
    }
    
    console.error('[ErrorHandler] Unhandled promise rejection:', reason)
  }
  
  overrideDocumentWrite() {
    // Store original document.write
    const originalWrite = document.write
    const originalWriteln = document.writeln
    
    // Override to prevent issues
    document.write = function(content) {
      console.warn('[ErrorHandler] Blocked document.write:', content.substring(0, 100))
      
      // Allow specific safe writes
      if (content.includes('@ungap/custom-elements-builtin')) {
        // Load the polyfill safely without document.write
        const script = document.createElement('script')
        script.src = 'https://unpkg.com/@ungap/custom-elements-builtin'
        script.async = true
        document.head.appendChild(script)
        return
      }
      
      // Block other writes during page load
      if (document.readyState === 'loading') {
        console.warn('[ErrorHandler] Blocked document.write during page load')
        return
      }
      
      // Allow writes after page load (safer)
      originalWrite.call(document, content)
    }
    
    document.writeln = function(content) {
      document.write(content + '\n')
    }
  }
  
  handleVisibilityChange() {
    // Detect when page goes blank
    const checkVisibility = () => {
      if (document.body && document.body.children.length === 0) {
        console.error('[ErrorHandler] Page appears blank, attempting recovery...')
        this.recoverPage()
      }
    }
    
    // Check periodically for first few seconds
    let checks = 0
    const interval = setInterval(() => {
      checks++
      checkVisibility()
      
      if (checks > 10) {
        clearInterval(interval)
      }
    }, 500)
  }
  
  recoverPage() {
    // Attempt to recover the page by reloading without cache
    console.log('[ErrorHandler] Attempting page recovery...')
    
    // Try Turbo reload first
    if (window.Turbo) {
      console.log('[ErrorHandler] Using Turbo to reload page...')
      window.Turbo.cache.clear()
      window.Turbo.visit(window.location.href, { action: 'replace' })
    } else {
      // Fallback to regular reload
      console.log('[ErrorHandler] Using location.reload...')
      window.location.reload(true)
    }
  }
}