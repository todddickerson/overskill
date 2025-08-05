import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["fileInput", "formFileInput", "uploadForm", "generateButton"]
  static values = { appId: Number }
  
  connect() {
    this.appIdValue = this.getAppId()
  }

  getAppId() {
    // Extract app ID from the URL or data attributes
    const pathParts = window.location.pathname.split('/')
    const appIndex = pathParts.indexOf('apps')
    return appIndex !== -1 ? parseInt(pathParts[appIndex + 1]) : null
  }

  async generate(event) {
    event.preventDefault()
    
    if (!this.appIdValue) {
      console.error('App ID not found')
      return
    }
    
    try {
      // Show loading state
      this.showLoadingState(event.target, 'Generating...')
      
      const response = await fetch(`/account/apps/${this.appIdValue}/generate_logo`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        }
      })
      
      if (response.ok) {
        const result = await response.json()
        if (result.success) {
          this.showSuccess('Logo generated successfully!')
          // Refresh the page to show the new logo
          setTimeout(() => window.location.reload(), 1000)
        } else {
          this.showError(result.error || 'Failed to generate logo')
        }
      } else {
        this.showError('Failed to generate logo')
      }
    } catch (error) {
      console.error('Logo generation error:', error)
      this.showError('An error occurred while generating the logo')
    } finally {
      this.resetButtonState(event.target, 'Generate')
    }
  }

  handleFileSelect(event) {
    const file = event.target.files[0]
    if (file) {
      console.log("File selected:", file.name)
      this.uploadFileViaForm(file)
    }
  }
  
  async uploadFileViaForm(file) {
    // Set the file on the form's file input
    const dataTransfer = new DataTransfer()
    dataTransfer.items.add(file)
    this.formFileInputTarget.files = dataTransfer.files
    
    // Submit the form
    const form = this.uploadFormTarget
    const formData = new FormData(form)
    
    try {
      const response = await fetch(form.action, {
        method: 'POST',
        body: formData,
        headers: {
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
          'Accept': 'application/json'
        }
      })
      
      if (response.ok) {
        console.log("Logo uploaded successfully")
        this.showSuccess('Logo uploaded successfully!')
        // Reload to show the new logo
        setTimeout(() => window.location.reload(), 1000)
      } else {
        const error = await response.json()
        console.error("Upload failed:", error)
        this.showError(error.error || "Failed to upload logo")
      }
    } catch (error) {
      console.error("Upload error:", error)
      this.showError("Failed to upload logo")
    }
  }

  upload(event) {
    event.preventDefault()
    // The file input click is handled by the label in the HTML
    console.log("Upload button clicked - file input should be triggered by label")
  }

  async uploadFile(file, button) {
    try {
      // Validate file type
      if (!file.type.startsWith('image/')) {
        this.showError('Please select an image file')
        return
      }
      
      // Validate file size (max 5MB)
      if (file.size > 5 * 1024 * 1024) {
        this.showError('File size must be less than 5MB')
        return
      }
      
      this.showLoadingState(button, 'Uploading...')
      
      const formData = new FormData()
      formData.append('logo', file)
      
      const response = await fetch(`/account/apps/${this.appIdValue}/upload_logo`, {
        method: 'POST',
        headers: {
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        },
        body: formData
      })
      
      if (response.ok) {
        const result = await response.json()
        if (result.success) {
          this.showSuccess('Logo uploaded successfully!')
          // Refresh the page to show the new logo
          setTimeout(() => window.location.reload(), 1000)
        } else {
          this.showError(result.error || 'Failed to upload logo')
        }
      } else {
        this.showError('Failed to upload logo')
      }
    } catch (error) {
      console.error('Logo upload error:', error)
      this.showError('An error occurred while uploading the logo')
    } finally {
      this.resetButtonState(button, 'Upload')
    }
  }

  showLoadingState(button, text) {
    button.disabled = true
    button.innerHTML = `
      <div class="animate-spin rounded-full h-3 w-3 border-2 border-white border-t-transparent mr-1"></div>
      ${text}
    `
  }

  resetButtonState(button, originalText) {
    button.disabled = false
    button.innerHTML = `<i class="fas fa-${originalText === 'Generate' ? 'magic' : 'upload'} mr-1"></i>${originalText}`
  }

  showSuccess(message) {
    this.showNotification(message, 'success')
  }

  showError(message) {
    this.showNotification(message, 'error')
  }

  showNotification(message, type) {
    // Remove existing notifications
    const existing = document.querySelector('.logo-notification')
    if (existing) existing.remove()
    
    const notification = document.createElement('div')
    notification.className = `logo-notification fixed top-4 right-4 px-4 py-2 rounded-lg shadow-lg z-50 flex items-center space-x-2 ${
      type === 'success' ? 'bg-green-500 text-white' : 'bg-red-500 text-white'
    }`
    
    notification.innerHTML = `
      <i class="fas fa-${type === 'success' ? 'check-circle' : 'exclamation-triangle'}"></i>
      <span class="text-sm font-medium">${message}</span>
    `
    
    document.body.appendChild(notification)
    
    // Auto-remove after 3 seconds
    setTimeout(() => {
      if (notification) notification.remove()
    }, 3000)
  }
}