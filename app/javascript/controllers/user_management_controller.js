import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["inviteModal", "searchInput", "roleFilter", "statusFilter", "usersList"]
  static values = { appId: Number }
  
  connect() {
    // Load users when connected
    this.loadUsers()
  }
  
  showInviteModal() {
    this.inviteModalTarget.classList.remove('hidden')
  }
  
  hideInviteModal() {
    this.inviteModalTarget.classList.add('hidden')
  }
  
  inviteUser(event) {
    event.preventDefault()
    
    const formData = new FormData(event.currentTarget)
    const email = formData.get('email')
    const role = formData.get('role')
    const message = formData.get('message')
    
    // Simulate sending invitation
    console.log('Inviting user:', { email, role, message })
    
    // Show success message
    this.showNotification('Invitation sent successfully!')
    
    // Close modal and reset form
    this.hideInviteModal()
    event.currentTarget.reset()
  }
  
  searchUsers(event) {
    const searchTerm = event.currentTarget.value.toLowerCase()
    this.filterUsersList(searchTerm)
  }
  
  filterUsers() {
    const searchTerm = this.hasSearchInputTarget ? this.searchInputTarget.value.toLowerCase() : ''
    this.filterUsersList(searchTerm)
  }
  
  filterUsersList(searchTerm) {
    const roleFilter = this.hasRoleFilterTarget ? this.roleFilterTarget.value : ''
    const statusFilter = this.hasStatusFilterTarget ? this.statusFilterTarget.value : ''
    
    // In a real app, this would make an API call
    // For now, just filter the DOM elements
    const rows = this.usersListTarget.querySelectorAll('tr')
    
    rows.forEach(row => {
      const userText = row.textContent.toLowerCase()
      const roleElement = row.querySelector('[class*="rounded-full"]')
      const roleText = roleElement ? roleElement.textContent.trim().toLowerCase() : ''
      
      let show = true
      
      // Search filter
      if (searchTerm && !userText.includes(searchTerm)) {
        show = false
      }
      
      // Role filter
      if (roleFilter && !roleText.includes(roleFilter.toLowerCase())) {
        show = false
      }
      
      // Status filter (would need data attributes in real implementation)
      
      row.style.display = show ? '' : 'none'
    })
  }
  
  loadUsers() {
    // In a real app, this would fetch users from the API
    console.log('Loading users for app:', this.appIdValue)
  }
  
  showNotification(message) {
    // Create and show a notification
    const notification = document.createElement('div')
    notification.className = 'fixed top-4 right-4 bg-green-500 text-white px-6 py-3 rounded-lg shadow-lg z-50'
    notification.textContent = message
    
    document.body.appendChild(notification)
    
    setTimeout(() => {
      notification.remove()
    }, 3000)
  }
}