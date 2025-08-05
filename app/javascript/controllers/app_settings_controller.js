import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["variablesList"]
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
}