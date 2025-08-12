// Stimulus controller for chat progress and real-time updates
import { Controller } from "@hotwired/stimulus"
import { CableReady } from "cable_ready"

export default class extends Controller {
  static targets = [
    "progressBar", 
    "phaseList", 
    "fileTree", 
    "buildOutput",
    "errorPanel",
    "approvalPanel",
    "dependencyPanel"
  ]
  
  static values = {
    messageId: Number,
    channel: String
  }
  
  connect() {
    // Subscribe to CableReady broadcasts
    if (this.hasChannelValue) {
      CableReady.subscribe(this.channelValue, this.handleCableReady.bind(this))
    }
    
    // Initialize animations
    this.initializeAnimations()
    
    // Set up auto-scroll for build output
    if (this.hasBuildOutputTarget) {
      this.setupAutoScroll()
    }
  }
  
  disconnect() {
    if (this.hasChannelValue) {
      CableReady.unsubscribe(this.channelValue)
    }
  }
  
  // Handle CableReady operations
  handleCableReady(operations) {
    // Process any custom events from CableReady
    operations.forEach(operation => {
      if (operation.name === 'dispatch_event') {
        this.handleCustomEvent(operation.detail)
      }
    })
  }
  
  // Handle custom events
  handleCustomEvent(detail) {
    switch(detail.name) {
      case 'build:output:scroll':
        this.scrollBuildOutput()
        break
      case 'generation:complete:success':
        this.celebrateSuccess()
        break
      case 'approval:requested':
        this.highlightApprovalPanel()
        break
    }
  }
  
  // Initialize animations on connect
  initializeAnimations() {
    // Add subtle entrance animations to elements
    const elements = this.element.querySelectorAll('[data-animate]')
    elements.forEach((el, index) => {
      setTimeout(() => {
        el.classList.add('animate-fade-in')
      }, index * 50)
    })
  }
  
  // Auto-scroll build output
  setupAutoScroll() {
    this.buildOutputTarget.addEventListener('DOMNodeInserted', () => {
      this.scrollBuildOutput()
    })
  }
  
  scrollBuildOutput() {
    if (this.hasBuildOutputTarget) {
      this.buildOutputTarget.scrollTop = this.buildOutputTarget.scrollHeight
    }
  }
  
  // Success celebration animation
  celebrateSuccess() {
    // Add success animation classes
    this.element.classList.add('ring-2', 'ring-green-500', 'ring-opacity-50')
    
    // Create confetti effect (optional)
    this.createConfetti()
    
    // Remove animation after delay
    setTimeout(() => {
      this.element.classList.remove('ring-2', 'ring-green-500', 'ring-opacity-50')
    }, 3000)
  }
  
  // Highlight approval panel when action needed
  highlightApprovalPanel() {
    if (this.hasApprovalPanelTarget) {
      this.approvalPanelTarget.classList.add('animate-pulse', 'ring-2', 'ring-blue-500')
      
      // Remove highlight after user interaction
      this.approvalPanelTarget.addEventListener('click', () => {
        this.approvalPanelTarget.classList.remove('animate-pulse', 'ring-2', 'ring-blue-500')
      }, { once: true })
    }
  }
  
  // Create simple confetti effect
  createConfetti() {
    const colors = ['#10b981', '#3b82f6', '#f59e0b', '#ef4444']
    const confettiCount = 30
    
    for (let i = 0; i < confettiCount; i++) {
      const confetti = document.createElement('div')
      confetti.className = 'absolute w-2 h-2 rounded-full animate-confetti'
      confetti.style.backgroundColor = colors[Math.floor(Math.random() * colors.length)]
      confetti.style.left = `${Math.random() * 100}%`
      confetti.style.animationDelay = `${Math.random() * 0.5}s`
      confetti.style.animationDuration = `${1 + Math.random()}s`
      
      this.element.appendChild(confetti)
      
      // Remove confetti after animation
      setTimeout(() => confetti.remove(), 2000)
    }
  }
  
  // File tree interactions
  expandFileTree() {
    if (this.hasFileTreeTarget) {
      this.fileTreeTarget.classList.remove('max-h-64')
      this.fileTreeTarget.classList.add('max-h-none')
    }
  }
  
  collapseFileTree() {
    if (this.hasFileTreeTarget) {
      this.fileTreeTarget.classList.add('max-h-64')
      this.fileTreeTarget.classList.remove('max-h-none')
    }
  }
  
  // Copy file path to clipboard
  copyFilePath(event) {
    const path = event.currentTarget.dataset.path
    navigator.clipboard.writeText(path)
    
    // Show feedback
    const originalText = event.currentTarget.textContent
    event.currentTarget.textContent = 'Copied!'
    setTimeout(() => {
      event.currentTarget.textContent = originalText
    }, 1500)
  }
}