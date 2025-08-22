// Stimulus controller for chat progress and real-time updates
import { Controller } from "@hotwired/stimulus"
import consumer from "../channels/consumer"

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
    appId: String,
    channel: String
  }
  
  connect() {
    // Subscribe to unified app channel for real-time updates
    if (this.hasAppIdValue) {
      this.subscription = consumer.subscriptions.create(
        { 
          channel: "UnifiedAppChannel",
          app_id: this.appIdValue
        },
        {
          received: (data) => {
            // Filter to only handle chat/progress updates for our message
            if (data.message_id == this.messageIdValue || data.type?.includes('progress')) {
              this.handleChannelData(data)
            }
          }
        }
      )
    }
    
    // Initialize animations
    this.initializeAnimations()
    
    // Set up auto-scroll for build output
    if (this.hasBuildOutputTarget) {
      this.setupAutoScroll()
    }
  }
  
  disconnect() {
    if (this.subscription) {
      this.subscription.unsubscribe()
    }
  }
  
  // Handle channel data from Action Cable
  handleChannelData(data) {
    // Handle different types of updates
    switch(data.action) {
      case 'update_progress':
        this.updateProgress(data)
        break
      case 'add_file':
        this.addFileToTree(data)
        break
      case 'update_build_output':
        this.appendBuildOutput(data)
        break
      case 'dispatch_event':
        this.handleCustomEvent(data)
        break
    }
  }
  
  // Handle custom events
  handleCustomEvent(data) {
    switch(data.event_name) {
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
  
  // Update progress bar
  updateProgress(data) {
    if (this.hasProgressBarTarget && data.html) {
      this.progressBarTarget.innerHTML = data.html
    }
  }
  
  // Add file to tree
  addFileToTree(data) {
    if (this.hasFileTreeTarget && data.html) {
      this.fileTreeTarget.insertAdjacentHTML('beforeend', data.html)
    }
  }
  
  // Append build output
  appendBuildOutput(data) {
    if (this.hasBuildOutputTarget && data.line) {
      const line = document.createElement('div')
      line.className = data.stream === 'stderr' ? 'text-red-400' : 'text-gray-300'
      line.textContent = data.line
      this.buildOutputTarget.appendChild(line)
      this.scrollBuildOutput()
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