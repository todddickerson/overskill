import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal", "content", "previewUrl", "productionUrl", "visitorCount", "updateButton", "todayVisitors", "visitorChart", "totalVersions", "lastUpdated", "deployStatus", "deployButton"]
  static values = { appId: String }
  
  publishedUrl = null  // Store the correct URL for "View Live Site"
  
  connect() {
    console.log('PublishModalController connected', this.element)
    console.log('App ID value:', this.appIdValue)
    console.log('Has modal target:', this.hasModalTarget)
    // Load current URLs and visitor count
    this.loadAppData()
  }
  
  open() {
    console.log('PublishModalController.open() called')
    console.log('Has modal target:', this.hasModalTarget)
    console.log('Modal target:', this.modalTarget)
    
    if (this.hasModalTarget) {
      console.log('Opening modal - removing hidden class')
      this.modalTarget.classList.remove("hidden")
      document.body.style.overflow = "hidden"
    } else {
      console.log('ERROR: No modal target found!')
    }
  }
  
  close(event) {
    if (event) event.preventDefault()
    if (this.hasModalTarget) {
      this.modalTarget.classList.add("hidden")
      document.body.style.overflow = ""
    }
  }
  
  // Close modal when clicking outside
  closeOnBackdrop(event) {
    if (event.target === this.modalTarget) {
      this.close()
    }
  }
  
  async loadAppData() {
    try {
      const response = await fetch(`/account/apps/${this.appIdValue}/deployment_info.json`)
      if (response.ok) {
        const data = await response.json()
        this.updateUrls(data)
        this.updateVisitorAnalytics(data)
      }
    } catch (error) {
      console.error("Failed to load app data:", error)
    }
  }
  
  updateUrls(data) {
    // Store the published URL for "View Live Site" button
    this.publishedUrl = data.published_url || data.preview_url
    
    if (this.hasPreviewUrlTarget && data.preview_url) {
      const url = new URL(data.preview_url)
      this.previewUrlTarget.textContent = url.hostname
    }
    
    if (this.hasProductionUrlTarget) {
      if (data.production_url) {
        const url = new URL(data.production_url)
        this.productionUrlTarget.textContent = url.hostname
      } else if (data.is_published === false && data.preview_url) {
        // If not published yet, show preview URL as the production URL placeholder
        const url = new URL(data.preview_url)
        this.productionUrlTarget.textContent = `${url.hostname} (not published yet)`
      }
    }
  }
  
  updateVisitorAnalytics(data) {
    // Update visitor count
    if (this.hasVisitorCountTarget) {
      this.visitorCountTarget.textContent = data.visitor_count || 0
    }
    
    // Update today's visitors (last item in daily_visitors array)
    if (this.hasTodayVisitorsTarget && data.daily_visitors) {
      const todayCount = data.daily_visitors[data.daily_visitors.length - 1] || 0
      this.todayVisitorsTarget.textContent = `${todayCount} today`
    }
    
    // Update visitor chart
    if (this.hasVisitorChartTarget && data.daily_visitors) {
      this.updateVisitorChart(data.daily_visitors)
    }
    
    // Update additional metrics
    if (this.hasTotalVersionsTarget) {
      this.totalVersionsTarget.textContent = data.total_versions || 0
    }
    
    if (this.hasLastUpdatedTarget && data.last_updated) {
      const lastUpdated = new Date(data.last_updated)
      const now = new Date()
      const diffInHours = Math.floor((now - lastUpdated) / (1000 * 60 * 60))
      
      let timeText
      if (diffInHours < 1) {
        timeText = "Just now"
      } else if (diffInHours < 24) {
        timeText = `${diffInHours}h ago`
      } else {
        const diffInDays = Math.floor(diffInHours / 24)
        timeText = `${diffInDays}d ago`
      }
      
      this.lastUpdatedTarget.textContent = timeText
    }
  }
  
  updateVisitorChart(dailyVisitors) {
    if (!dailyVisitors || dailyVisitors.length === 0) return
    
    const maxVisitors = Math.max(...dailyVisitors, 1)
    const bars = this.visitorChartTarget.children
    
    dailyVisitors.forEach((count, index) => {
      if (bars[index]) {
        const height = Math.max((count / maxVisitors) * 100, 8) // Minimum 8% height
        const isToday = index === dailyVisitors.length - 1
        
        bars[index].style.height = `${height}%`
        bars[index].className = `flex-1 rounded-t min-h-[8px] ${isToday ? 'bg-blue-500' : 'bg-gray-300'}`
      }
    })
  }
  
  async update(event) {
    event.preventDefault()
    
    // Show loading state
    const originalText = this.updateButtonTarget.textContent
    this.updateButtonTarget.textContent = "Updating..."
    this.updateButtonTarget.disabled = true
    
    try {
      // Trigger deployment
      const response = await fetch(`/account/apps/${this.appIdValue}/deploy`, {
        method: 'POST',
        headers: {
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ environment: 'production' })
      })
      
      if (response.ok) {
        // Show success
        this.updateButtonTarget.textContent = "Updated!"
        this.updateButtonTarget.classList.remove("bg-blue-600", "hover:bg-blue-700")
        this.updateButtonTarget.classList.add("bg-green-600")
        
        // Reload app data after deployment
        setTimeout(() => {
          this.loadAppData()
          this.updateButtonTarget.textContent = originalText
          this.updateButtonTarget.classList.remove("bg-green-600")
          this.updateButtonTarget.classList.add("bg-blue-600", "hover:bg-blue-700")
          this.updateButtonTarget.disabled = false
        }, 2000)
      } else {
        throw new Error("Deployment failed")
      }
    } catch (error) {
      console.error("Update failed:", error)
      this.updateButtonTarget.textContent = "Update Failed"
      this.updateButtonTarget.classList.remove("bg-blue-600", "hover:bg-blue-700")
      this.updateButtonTarget.classList.add("bg-red-600")
      
      setTimeout(() => {
        this.updateButtonTarget.textContent = originalText
        this.updateButtonTarget.classList.remove("bg-red-600")
        this.updateButtonTarget.classList.add("bg-blue-600", "hover:bg-blue-700")
        this.updateButtonTarget.disabled = false
      }, 3000)
    }
  }
  
  async copyPreviewUrl(event) {
    event.preventDefault()
    const url = `https://${this.previewUrlTarget.textContent}`
    await this.copyToClipboard(url, event.currentTarget)
  }
  
  async copyProductionUrl(event) {
    event.preventDefault()
    const url = `https://${this.productionUrlTarget.textContent}`
    await this.copyToClipboard(url, event.currentTarget)
  }
  
  async copyToClipboard(text, button) {
    try {
      await navigator.clipboard.writeText(text)
      
      // Show success feedback
      const originalHtml = button.innerHTML
      button.innerHTML = '<svg class="w-5 h-5 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path></svg>'
      
      setTimeout(() => {
        button.innerHTML = originalHtml
      }, 2000)
    } catch (error) {
      console.error("Failed to copy:", error)
    }
  }
  
  openInNewTab(event) {
    event.preventDefault()
    // Use the published URL which is either production (if published) or preview (if not)
    const url = this.publishedUrl || `https://${this.previewUrlTarget.textContent}`
    
    // Ensure the URL has proper protocol
    const finalUrl = url.startsWith('http') ? url : `https://${url}`
    window.open(finalUrl, '_blank')
  }
  
  async deployProduction(event) {
    event.preventDefault()
    console.log('Deploying to production...')
    
    // Show loading state
    const button = event.currentTarget
    const originalContent = button.innerHTML
    button.disabled = true
    button.innerHTML = '<i class="fas fa-spinner fa-spin"></i> <span>Deploying...</span>'
    
    // Show enhanced deploy status with progress
    this.showDeployProgress('Starting deployment...')
    
    try {
      const response = await fetch(`/account/apps/${this.appIdValue}/deploy`, {
        method: 'POST',
        headers: {
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ environment: 'production' })
      })
      
      if (response.ok) {
        const result = await response.json()
        console.log('Deploy response:', result)
        
        // Start polling for deployment status
        this.pollDeploymentStatus(button, originalContent)
      } else {
        const errorData = await response.json().catch(() => ({}))
        throw new Error(errorData.error || 'Deployment failed')
      }
    } catch (error) {
      console.error('Deploy failed:', error)
      this.showDeployError(error.message, button, originalContent)
    }
  }
  
  showDeployProgress(message, percentage = null) {
    if (this.hasDeployStatusTarget) {
      this.deployStatusTarget.classList.remove('hidden')
      
      // Update the progress message
      let progressHtml = `
        <div class="flex items-center space-x-3">
          <i class="fas fa-spinner fa-spin text-blue-600 dark:text-blue-400"></i>
          <div class="flex-1">
            <div class="text-sm text-blue-700 dark:text-blue-300">${message}</div>
            ${percentage !== null ? `
              <div class="w-full bg-blue-200 dark:bg-blue-800 rounded-full h-2 mt-2">
                <div class="bg-blue-600 dark:bg-blue-400 h-2 rounded-full transition-all duration-500" style="width: ${percentage}%"></div>
              </div>
            ` : ''}
          </div>
        </div>
      `
      
      this.deployStatusTarget.innerHTML = progressHtml
      this.deployStatusTarget.className = 'mt-4 p-3 bg-blue-50 dark:bg-blue-900/20 rounded-lg border border-blue-200 dark:border-blue-800'
    }
  }
  
  showDeployError(message, button, originalContent) {
    // Show error in status
    if (this.hasDeployStatusTarget) {
      this.deployStatusTarget.innerHTML = `
        <div class="flex items-center space-x-2">
          <i class="fas fa-times-circle text-red-600 dark:text-red-400"></i>
          <span class="text-sm text-red-700 dark:text-red-300">${message}</span>
        </div>
      `
      this.deployStatusTarget.className = 'mt-4 p-3 bg-red-50 dark:bg-red-900/20 rounded-lg border border-red-200 dark:border-red-800'
    }
    
    // Update button
    button.innerHTML = '<i class="fas fa-times"></i> <span>Deploy Failed</span>'
    button.classList.remove('bg-blue-600', 'hover:bg-blue-700')
    button.classList.add('bg-red-600')
    
    // Reset after delay
    setTimeout(() => {
      button.innerHTML = originalContent
      button.classList.remove('bg-red-600')
      button.classList.add('bg-blue-600', 'hover:bg-blue-700')
      button.disabled = false
      if (this.hasDeployStatusTarget) {
        this.deployStatusTarget.classList.add('hidden')
      }
    }, 5000)
  }
  
  async pollDeploymentStatus(button, originalContent) {
    let attempts = 0
    const maxAttempts = 30 // 30 attempts = 60 seconds max
    
    const poll = async () => {
      attempts++
      
      try {
        const response = await fetch(`/account/apps/${this.appIdValue}/deployment_info.json`)
        if (response.ok) {
          const data = await response.json()
          const status = data.deployment_status
          
          console.log('Deployment status:', status, 'Attempt:', attempts)
          
          if (status === 'deployed' || status === 'published') {
            // Success!
            this.showDeploySuccess(button, originalContent)
            return
          } else if (status === 'failed') {
            // Failed
            this.showDeployError('Deployment failed', button, originalContent)
            return
          } else if (status === 'deploying' || status === 'generating') {
            // Still in progress
            const percentage = Math.min((attempts / maxAttempts) * 80, 80) // Max 80% until completion
            this.showDeployProgress('Deploying to Cloudflare...', percentage)
            
            if (attempts < maxAttempts) {
              setTimeout(poll, 2000) // Poll every 2 seconds
            } else {
              this.showDeployError('Deployment timed out', button, originalContent)
            }
          } else {
            // Unknown status, keep polling
            if (attempts < maxAttempts) {
              setTimeout(poll, 2000)
            } else {
              this.showDeployError('Deployment status unknown', button, originalContent)
            }
          }
        } else {
          throw new Error('Failed to check deployment status')
        }
      } catch (error) {
        console.error('Polling error:', error)
        if (attempts < maxAttempts) {
          setTimeout(poll, 2000)
        } else {
          this.showDeployError('Could not verify deployment status', button, originalContent)
        }
      }
    }
    
    // Start polling after a brief delay
    setTimeout(poll, 3000)
  }
  
  showDeploySuccess(button, originalContent) {
    // Show success in status
    if (this.hasDeployStatusTarget) {
      this.deployStatusTarget.innerHTML = `
        <div class="flex items-center space-x-2">
          <i class="fas fa-check-circle text-green-600 dark:text-green-400"></i>
          <span class="text-sm text-green-700 dark:text-green-300">Successfully deployed!</span>
        </div>
      `
      this.deployStatusTarget.className = 'mt-4 p-3 bg-green-50 dark:bg-green-900/20 rounded-lg border border-green-200 dark:border-green-800'
    }
    
    // Update button
    button.innerHTML = '<i class="fas fa-check"></i> <span>Deployed!</span>'
    button.classList.remove('bg-blue-600', 'hover:bg-blue-700')
    button.classList.add('bg-green-600')
    
    // Reload app data and reset
    setTimeout(() => {
      this.loadAppData()
      button.innerHTML = originalContent
      button.classList.remove('bg-green-600')
      button.classList.add('bg-blue-600', 'hover:bg-blue-700')
      button.disabled = false
      if (this.hasDeployStatusTarget) {
        this.deployStatusTarget.classList.add('hidden')
      }
    }, 3000)
  }
  
  async deployPreview(event) {
    event.preventDefault()
    console.log('Deploying to preview...')
    
    // Show loading state
    const button = event.currentTarget
    const originalContent = button.innerHTML
    button.disabled = true
    button.innerHTML = '<i class="fas fa-spinner fa-spin"></i> <span>Updating...</span>'
    
    try {
      const response = await fetch(`/account/apps/${this.appIdValue}/deploy`, {
        method: 'POST',
        headers: {
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ environment: 'preview' })
      })
      
      if (response.ok) {
        button.innerHTML = '<i class="fas fa-check"></i> <span>Updated!</span>'
        button.classList.remove('bg-gray-600', 'hover:bg-gray-700')
        button.classList.add('bg-green-600')
        
        setTimeout(() => {
          button.innerHTML = originalContent
          button.classList.remove('bg-green-600')
          button.classList.add('bg-gray-600', 'hover:bg-gray-700')
          button.disabled = false
        }, 2000)
      } else {
        throw new Error('Update failed')
      }
    } catch (error) {
      console.error('Update failed:', error)
      button.innerHTML = '<i class="fas fa-times"></i> <span>Update Failed</span>'
      button.classList.remove('bg-gray-600', 'hover:bg-gray-700')
      button.classList.add('bg-red-600')
      
      setTimeout(() => {
        button.innerHTML = originalContent
        button.classList.remove('bg-red-600')
        button.classList.add('bg-gray-600', 'hover:bg-gray-700')
        button.disabled = false
      }, 3000)
    }
  }
}