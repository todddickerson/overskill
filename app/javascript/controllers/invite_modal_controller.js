import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal", "form", "emailInput", "submitButton", "successMessage", "successText"]
  static values = { 
    appId: String,
    teamId: String 
  }
  
  open() {
    console.log('InviteModalController.open() called')
    if (this.hasModalTarget) {
      this.modalTarget.classList.remove("hidden")
      document.body.style.overflow = "hidden"
      
      // Reset form if it exists
      if (this.hasFormTarget) {
        this.formTarget.reset()
        this.showForm()
      }
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
  
  async submitInvite(event) {
    event.preventDefault()
    
    const form = this.formTarget
    const formData = new FormData(form)
    
    // Show loading state
    this.setLoadingState(true)
    
    try {
      const response = await fetch(form.action, {
        method: 'POST',
        body: formData,
        headers: {
          'X-Requested-With': 'XMLHttpRequest',
          'Accept': 'application/json'
        }
      })
      
      const data = await response.json()
      
      if (response.ok) {
        // Show success message
        this.showSuccess(formData.get('invitation[email]'))
        
        // Also open share modal if user wants to share the app
        setTimeout(() => {
          this.close()
          this.openShareModal()
        }, 2000)
      } else {
        // Handle errors
        const errorMessage = data.errors ? Object.values(data.errors).flat().join(', ') : 'Failed to send invitation'
        this.showError(errorMessage)
      }
    } catch (error) {
      console.error('Failed to send invitation:', error)
      this.showError('Failed to send invitation. Please try again.')
    } finally {
      this.setLoadingState(false)
    }
  }
  
  showSuccess(email) {
    if (this.hasSuccessMessageTarget && this.hasFormTarget) {
      this.formTarget.classList.add('hidden')
      this.successMessageTarget.classList.remove('hidden')
      
      if (this.hasSuccessTextTarget) {
        this.successTextTarget.textContent = `An invitation has been sent to ${email}`
      }
    }
  }
  
  showError(message) {
    // Create and show error message
    const errorDiv = document.createElement('div')
    errorDiv.className = 'bg-red-50 dark:bg-red-900/20 rounded-lg p-3 mt-3'
    errorDiv.innerHTML = `
      <p class="text-sm text-red-600 dark:text-red-400">
        <i class="fas fa-exclamation-circle mr-1"></i>
        ${message}
      </p>
    `
    this.formTarget.appendChild(errorDiv)
    
    // Remove error after 5 seconds
    setTimeout(() => errorDiv.remove(), 5000)
  }
  
  showForm() {
    if (this.hasSuccessMessageTarget && this.hasFormTarget) {
      this.successMessageTarget.classList.add('hidden')
      this.formTarget.classList.remove('hidden')
    }
  }
  
  setLoadingState(loading) {
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.disabled = loading
      if (loading) {
        this.submitButtonTarget.innerHTML = '<i class="fas fa-spinner fa-spin mr-2"></i>Sending...'
      } else {
        this.submitButtonTarget.innerHTML = '<i class="fas fa-paper-plane mr-2"></i>Send Invitation'
      }
    }
  }
  
  async removeCollaborator(event) {
    const button = event.currentTarget
    const collaboratorId = button.dataset.collaboratorId
    
    if (!confirm('Remove this collaborator?')) return
    
    try {
      const response = await fetch(`/account/apps/${this.appIdValue}/collaborators/${collaboratorId}`, {
        method: 'DELETE',
        headers: {
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
          'X-Requested-With': 'XMLHttpRequest',
          'Accept': 'application/json'
        }
      })
      
      if (response.ok) {
        // Remove the collaborator element
        button.closest('.flex').remove()
      }
    } catch (error) {
      console.error('Failed to remove collaborator:', error)
    }
  }
  
  openShareModal() {
    // Find and open the share modal
    const shareModal = document.querySelector('#share_modal')
    if (shareModal) {
      const controller = this.application.getControllerForElementAndIdentifier(shareModal, 'share-modal')
      if (controller && controller.open) {
        controller.open()
      }
    }
  }
}