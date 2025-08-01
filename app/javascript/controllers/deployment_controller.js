import { Controller } from "@hotwired/stimulus"
import consumer from "../channels/consumer"

export default class extends Controller {
  static targets = ["status", "button"]
  static values = { appId: String }

  connect() {
    this.subscription = consumer.subscriptions.create(
      { channel: "DeploymentChannel", app_id: this.appIdValue },
      {
        received: (data) => {
          this.updateStatus(data)
        }
      }
    )
  }

  disconnect() {
    if (this.subscription) {
      this.subscription.unsubscribe()
    }
  }

  deploy(event) {
    event.preventDefault()
    
    // Update button to show deploying state
    this.updateStatus({ status: 'deploying' })
    
    // Submit the form
    const form = event.target.closest('form')
    if (form) {
      form.requestSubmit()
    }
  }

  updateStatus(data) {
    const { status, message, deployment_url, deployed_at } = data
    
    if (this.hasStatusTarget) {
      switch (status) {
        case 'deploying':
          this.statusTarget.innerHTML = '<i class="fas fa-spinner fa-spin mr-1"></i> Deploying...'
          this.statusTarget.className = 'text-yellow-400'
          break
        case 'deployed':
          this.statusTarget.innerHTML = '<i class="fas fa-check mr-1"></i> Deployed'
          this.statusTarget.className = 'text-green-400'
          
          // Show success notification
          this.showNotification(`App deployed successfully! ${deployment_url}`, 'success')
          
          // Update any preview URLs if needed
          if (deployment_url) {
            this.updatePreviewUrls(deployment_url)
          }
          break
        case 'failed':
          this.statusTarget.innerHTML = '<i class="fas fa-exclamation-triangle mr-1"></i> Deploy Failed'
          this.statusTarget.className = 'text-red-400'
          
          // Show error notification
          this.showNotification(`Deployment failed: ${message}`, 'error')
          break
        default:
          this.statusTarget.innerHTML = '<i class="fas fa-cloud-upload-alt mr-1"></i> Deploy'
          this.statusTarget.className = ''
      }
    }
  }

  updatePreviewUrls(deploymentUrl) {
    // Update any "Open Preview" links to use the deployed URL
    const previewLinks = document.querySelectorAll('[data-deployment-preview]')
    previewLinks.forEach(link => {
      link.href = deploymentUrl
      link.classList.remove('text-gray-400')
      link.classList.add('text-blue-400')
    })
  }

  showNotification(message, type = 'info') {
    // Create a notification element
    const notification = document.createElement('div')
    notification.className = `fixed top-4 right-4 z-50 px-6 py-3 rounded-lg text-white text-sm max-w-md shadow-lg ${
      type === 'success' ? 'bg-green-600' : 
      type === 'error' ? 'bg-red-600' : 
      'bg-blue-600'
    }`
    
    notification.innerHTML = `
      <div class="flex items-center justify-between">
        <div class="flex items-center">
          <i class="fas fa-${type === 'success' ? 'check-circle' : type === 'error' ? 'exclamation-triangle' : 'info-circle'} mr-2"></i>
          <span>${message}</span>
        </div>
        <button class="ml-4 text-white hover:text-gray-200" onclick="this.parentElement.parentElement.remove()">
          <i class="fas fa-times"></i>
        </button>
      </div>
    `

    document.body.appendChild(notification)

    // Auto-remove after 8 seconds (longer for deployment messages)
    setTimeout(() => {
      if (notification.parentElement) {
        notification.remove()
      }
    }, 8000)
  }
}