import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "variablesList", "nameInput", "descriptionInput", "visibilitySelect",
    "frameworkSelect", "typeSelect"
  ]
  static values = { appId: String }
  
  connect() {
    console.log('AppSettingsController connected')
    this.appIdValue = this.appIdValue || this.getAppId()
  }

  getAppId() {
    // Extract app ID from the URL or data attributes
    const pathParts = window.location.pathname.split('/')
    const appIndex = pathParts.indexOf('apps')
    return appIndex !== -1 ? parseInt(pathParts[appIndex + 1]) : null
  }

  editApp(event) {
    event.preventDefault()
    
    if (!this.appIdValue) {
      console.error('App ID not found')
      return
    }
    
    // Navigate to the standard Rails edit form
    window.location.href = `/account/apps/${this.appIdValue}/edit`
  }

  editDescription(event) {
    event.preventDefault()
    
    if (!this.appIdValue) {
      console.error('App ID not found')
      return
    }
    
    // For now, also redirect to edit form - could be enhanced with inline editing later
    window.location.href = `/account/apps/${this.appIdValue}/edit`
  }

  duplicateApp(event) {
    event.preventDefault()
    
    if (!this.appIdValue) {
      console.error('App ID not found')
      return
    }
    
    // TODO: Implement app duplication functionality
    console.log('Duplicate app functionality not yet implemented')
    alert('App duplication feature coming soon!')
  }
  
  addVariable() {
    const variableRow = document.createElement('div')
    variableRow.className = 'flex items-center space-x-2'
    variableRow.innerHTML = `
      <input type="text" placeholder="KEY" class="flex-1 px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-gray-900 dark:text-white font-mono text-sm">
      <input type="text" placeholder="Value" class="flex-1 px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-gray-900 dark:text-white text-sm">
      <button class="text-gray-400 hover:text-red-600 dark:hover:text-red-400" title="Remove variable" data-action="click->app-settings#removeVariable">
        <i class="fas fa-trash-alt"></i>
      </button>
    `
    
    // Remove the "no variables" message if it exists
    const emptyMessage = this.variablesListTarget.querySelector('p')
    if (emptyMessage) {
      emptyMessage.remove()
    }
    
    this.variablesListTarget.appendChild(variableRow)
  }
  
  removeVariable(event) {
    const row = event.currentTarget.closest('.flex')
    row.remove()
    
    // Show empty message if no variables left
    if (this.variablesListTarget.children.length === 0) {
      this.variablesListTarget.innerHTML = '<p class="text-sm text-gray-500 dark:text-gray-400">No environment variables configured yet.</p>'
    }
  }
  
  // Modal-specific methods
  async saveSettings(event) {
    event.preventDefault()
    
    const data = {
      app: {
        name: this.hasNameInputTarget ? this.nameInputTarget.value : null,
        description: this.hasDescriptionInputTarget ? this.descriptionInputTarget.value : null,
        visibility: this.hasVisibilitySelectTarget ? this.visibilitySelectTarget.value : null,
        framework: this.hasFrameworkSelectTarget ? this.frameworkSelectTarget.value : null,
        app_type: this.hasTypeSelectTarget ? this.typeSelectTarget.value : null
      }
    }
    
    // Remove null values
    Object.keys(data.app).forEach(key => {
      if (data.app[key] === null) delete data.app[key]
    })
    
    try {
      const response = await fetch(`/account/apps/${this.appIdValue}`, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        },
        body: JSON.stringify(data)
      })
      
      if (response.ok) {
        // Show success message
        this.showNotification('Settings saved successfully!', 'success')
        
        // Close modal
        this.closeModal()
        
        // Optionally reload the page to reflect changes
        setTimeout(() => {
          window.location.reload()
        }, 1000)
      } else {
        throw new Error('Failed to save settings')
      }
    } catch (error) {
      console.error('Error saving settings:', error)
      this.showNotification('Failed to save settings', 'error')
    }
  }
  
  async generateLogo(event) {
    event.preventDefault()
    
    try {
      const response = await fetch(`/account/apps/${this.appIdValue}/generate_logo`, {
        method: 'POST',
        headers: {
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
          'Content-Type': 'application/json'
        }
      })
      
      if (response.ok) {
        this.showNotification('Logo generation started...', 'info')
      } else {
        throw new Error('Failed to start logo generation')
      }
    } catch (error) {
      console.error('Error generating logo:', error)
      this.showNotification('Failed to generate logo', 'error')
    }
  }
  
  uploadLogo(event) {
    event.preventDefault()
    
    // Create file input
    const fileInput = document.createElement('input')
    fileInput.type = 'file'
    fileInput.accept = 'image/*'
    
    fileInput.onchange = async (e) => {
      const file = e.target.files[0]
      if (!file) return
      
      const formData = new FormData()
      formData.append('logo', file)
      
      try {
        const response = await fetch(`/account/apps/${this.appIdValue}/upload_logo`, {
          method: 'POST',
          headers: {
            'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
          },
          body: formData
        })
        
        if (response.ok) {
          this.showNotification('Logo uploaded successfully!', 'success')
          setTimeout(() => window.location.reload(), 1000)
        } else {
          throw new Error('Failed to upload logo')
        }
      } catch (error) {
        console.error('Error uploading logo:', error)
        this.showNotification('Failed to upload logo', 'error')
      }
    }
    
    fileInput.click()
  }
  
  openPreview(event) {
    event.preventDefault()
    const previewUrl = event.currentTarget.closest('.flex').querySelector('input').value
    if (previewUrl) {
      window.open(previewUrl, '_blank')
    }
  }
  
  openProduction(event) {
    event.preventDefault()
    const productionUrl = event.currentTarget.closest('.flex').querySelector('input').value
    if (productionUrl) {
      window.open(productionUrl, '_blank')
    }
  }
  
  closeModal() {
    const modal = document.getElementById('app_settings_modal')
    if (modal) {
      modal.classList.add('hidden')
    }
  }
  
  showNotification(message, type = 'info') {
    // Create a simple notification (you could enhance this with a proper notification system)
    const notification = document.createElement('div')
    notification.className = `fixed top-4 right-4 z-50 px-4 py-2 rounded-md text-white ${
      type === 'success' ? 'bg-green-600' : 
      type === 'error' ? 'bg-red-600' : 
      'bg-blue-600'
    }`
    notification.textContent = message
    
    document.body.appendChild(notification)
    
    setTimeout(() => {
      notification.remove()
    }, 3000)
  }
}