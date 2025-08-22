import { Controller } from "@hotwired/stimulus"
import consumer from "../channels/consumer"

export default class extends Controller {
  static targets = ["timer", "progress", "status", "elapsed"]
  static values = { 
    appId: String, 
    messageId: String,
    estimatedSeconds: { type: Number, default: 120 }
  }

  connect() {
    console.log(`🔨 [BuildCountdown] Connecting to app ${this.appIdValue}, message ${this.messageIdValue}`)
    
    // Subscribe to the unified app channel for all updates (chat, deployment, build status)
    this.subscription = consumer.subscriptions.create(
      { 
        channel: "UnifiedAppChannel", 
        app_id: this.appIdValue 
      },
      {
        received: (data) => this.handleBuildUpdate(data)
      }
    )

    // Initialize timer state
    this.buildStartTime = null
    this.isBuilding = false
    this.elapsedSeconds = 0
    this.estimatedTotalSeconds = this.estimatedSecondsValue

    // Check initial state from the DOM to handle page refreshes
    this.initializeFromDOMState()

    // Start the countdown timer
    this.startTimer()
  }

  initializeFromDOMState() {
    // If this is a completed build, we don't need to start the timer
    if (this.hasStatusTarget) {
      const statusText = this.statusTarget.textContent.trim()
      if (statusText.includes('completed') || statusText.includes('failed')) {
        console.log(`🔨 [BuildCountdown] Build already completed: ${statusText}`)
        this.isBuilding = false
        return
      }
    }

    // If we're on a page with an active build, we might need to start counting from elapsed time
    if (this.hasElapsedTarget) {
      const elapsedText = this.elapsedTarget.textContent.trim()
      const elapsedMatch = elapsedText.match(/(\d+):(\d+)/)
      if (elapsedMatch) {
        const minutes = parseInt(elapsedMatch[1])
        const seconds = parseInt(elapsedMatch[2])
        this.elapsedSeconds = minutes * 60 + seconds
        this.buildStartTime = Date.now() - (this.elapsedSeconds * 1000)
        this.isBuilding = true
        console.log(`🔨 [BuildCountdown] Resuming build timer from ${this.elapsedSeconds}s elapsed`)
      }
    }
  }

  disconnect() {
    console.log(`🔨 [BuildCountdown] Disconnecting from app ${this.appIdValue}`)
    
    if (this.subscription) {
      this.subscription.unsubscribe()
    }
    
    if (this.timerInterval) {
      clearInterval(this.timerInterval)
    }
  }

  handleBuildUpdate(data) {
    // Only handle build status updates for this specific message
    if (data.type === 'build_status_update' && 
        data.message_id == this.messageIdValue) {
      
      console.log(`🔨 [BuildCountdown] Build update:`, data.build_status)
      
      const buildStatus = data.build_status
      this.updateBuildStatus(buildStatus)
    }
  }

  updateBuildStatus(status) {
    const { 
      status: buildPhase, 
      elapsed_seconds: elapsed, 
      estimated_total_seconds: estimated,
      conclusion,
      workflow_run_id 
    } = status

    // Update elapsed time from server
    if (elapsed !== undefined) {
      this.elapsedSeconds = elapsed
    }

    // Update estimated time if provided
    if (estimated !== undefined) {
      this.estimatedTotalSeconds = estimated
    }

    // Handle different build phases
    switch (buildPhase) {
      case 'in_progress':
      case 'queued':
        this.isBuilding = true
        this.buildStartTime = Date.now() - (this.elapsedSeconds * 1000)
        this.updateStatusText('Building app...', 'building')
        break
        
      case 'completed':
        this.isBuilding = false
        if (conclusion === 'success') {
          this.updateStatusText('Build completed successfully!', 'success')
          this.showCompletionAnimation()
        } else if (conclusion === 'failure') {
          this.updateStatusText('Build failed', 'failed')
          this.showFailureAnimation()
        }
        break
        
      case 'timeout':
        this.isBuilding = false
        this.updateStatusText('Build timed out', 'timeout')
        this.showTimeoutAnimation()
        break
        
      default:
        console.log(`🔨 [BuildCountdown] Unknown build status: ${buildPhase}`)
    }

    // Update the display immediately
    this.updateDisplay()
  }

  startTimer() {
    // Update display every second
    this.timerInterval = setInterval(() => {
      if (this.isBuilding && this.buildStartTime) {
        // Calculate elapsed time from when build started
        this.elapsedSeconds = Math.floor((Date.now() - this.buildStartTime) / 1000)
      }
      
      this.updateDisplay()
    }, 1000)
  }

  updateDisplay() {
    const remainingSeconds = Math.max(0, this.estimatedTotalSeconds - this.elapsedSeconds)
    const progressPercent = Math.min(100, (this.elapsedSeconds / this.estimatedTotalSeconds) * 100)

    // Update timer display
    if (this.hasTimerTarget) {
      if (this.isBuilding) {
        if (remainingSeconds > 0) {
          this.timerTarget.textContent = this.formatTime(remainingSeconds)
          this.timerTarget.className = 'text-sm text-blue-600 dark:text-blue-400 font-mono'
        } else {
          // Build is taking longer than expected
          const overtime = this.elapsedSeconds - this.estimatedTotalSeconds
          this.timerTarget.textContent = `+${this.formatTime(overtime)}`
          this.timerTarget.className = 'text-sm text-orange-600 dark:text-orange-400 font-mono animate-pulse'
        }
      } else {
        this.timerTarget.textContent = ''
      }
    }

    // Update progress bar
    if (this.hasProgressTarget) {
      this.progressTarget.style.width = `${progressPercent}%`
      
      // Change color if over time
      if (this.elapsedSeconds > this.estimatedTotalSeconds) {
        this.progressTarget.className = this.progressTarget.className.replace(
          'bg-gradient-to-r from-blue-500 to-blue-600',
          'bg-gradient-to-r from-orange-500 to-red-500'
        )
      }
    }

    // Update elapsed time
    if (this.hasElapsedTarget) {
      this.elapsedTarget.textContent = this.formatTime(this.elapsedSeconds)
    }
  }

  updateStatusText(text, type) {
    if (this.hasStatusTarget) {
      this.statusTarget.textContent = text
      
      // Update status styling based on type
      this.statusTarget.className = this.getStatusClass(type)
    }
  }

  getStatusClass(type) {
    const baseClass = 'text-xs font-medium'
    
    switch (type) {
      case 'building':
        return `${baseClass} text-blue-600 dark:text-blue-400`
      case 'success':
        return `${baseClass} text-green-600 dark:text-green-400`
      case 'failed':
        return `${baseClass} text-red-600 dark:text-red-400`
      case 'timeout':
        return `${baseClass} text-orange-600 dark:text-orange-400`
      default:
        return `${baseClass} text-gray-600 dark:text-gray-400`
    }
  }

  formatTime(seconds) {
    const minutes = Math.floor(seconds / 60)
    const remainingSeconds = seconds % 60
    
    if (minutes > 0) {
      return `${minutes}:${remainingSeconds.toString().padStart(2, '0')}`
    } else {
      return `0:${remainingSeconds.toString().padStart(2, '0')}`
    }
  }

  showCompletionAnimation() {
    // Add success animation to the container
    this.element.classList.add('animate-pulse')
    
    // Create success icon
    if (this.hasStatusTarget) {
      const icon = document.createElement('i')
      icon.className = 'fas fa-check-circle text-green-500 mr-1'
      this.statusTarget.prepend(icon)
    }
    
    // Remove animation after delay
    setTimeout(() => {
      this.element.classList.remove('animate-pulse')
    }, 2000)
  }

  showFailureAnimation() {
    // Add failure animation
    this.element.classList.add('animate-pulse')
    
    // Create failure icon
    if (this.hasStatusTarget) {
      const icon = document.createElement('i')
      icon.className = 'fas fa-exclamation-triangle text-red-500 mr-1'
      this.statusTarget.prepend(icon)
    }
    
    // Remove animation after delay
    setTimeout(() => {
      this.element.classList.remove('animate-pulse')
    }, 3000)
  }

  showTimeoutAnimation() {
    // Add timeout animation
    this.element.classList.add('animate-pulse')
    
    // Create timeout icon
    if (this.hasStatusTarget) {
      const icon = document.createElement('i')
      icon.className = 'fas fa-clock text-orange-500 mr-1'
      this.statusTarget.prepend(icon)
    }
    
    // Remove animation after delay
    setTimeout(() => {
      this.element.classList.remove('animate-pulse')
    }, 3000)
  }
}