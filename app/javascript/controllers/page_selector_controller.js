import { Controller } from "@hotwired/stimulus"

// Controller for selecting and switching between HTML pages in preview
export default class extends Controller {
  static targets = ["dropdown", "currentPageName"]
  static values = { 
    appId: String,
    currentPage: String 
  }
  
  connect() {
    console.log('PageSelectorController connected')
    console.log('App ID:', this.appIdValue)
    console.log('Current page:', this.currentPageValue)
    
    // Set initial page name
    if (this.hasCurrentPageNameTarget) {
      this.currentPageNameTarget.textContent = this.currentPageValue || 'index.html'
    }
    
    // Close dropdown when clicking outside
    this.boundClickOutside = this.clickOutside.bind(this)
    document.addEventListener('click', this.boundClickOutside)
  }
  
  disconnect() {
    document.removeEventListener('click', this.boundClickOutside)
  }
  
  toggleDropdown(event) {
    event.preventDefault()
    event.stopPropagation()
    
    console.log('Toggling dropdown')
    
    if (this.hasDropdownTarget) {
      this.dropdownTarget.classList.toggle('hidden')
    }
  }
  
  selectPage(event) {
    event.preventDefault()
    event.stopPropagation()
    
    const page = event.params.page
    console.log('Selected page:', page)
    
    // Update current page display
    this.currentPageValue = page
    if (this.hasCurrentPageNameTarget) {
      this.currentPageNameTarget.textContent = page
    }
    
    // Hide dropdown
    if (this.hasDropdownTarget) {
      this.dropdownTarget.classList.add('hidden')
    }
    
    // Update preview iframe
    this.updatePreview(page)
  }
  
  updatePreview(page) {
    console.log('Updating preview to page:', page)
    
    // Find all preview iframes (desktop and mobile)
    const iframes = document.querySelectorAll('[data-preview-device-target="iframe"], [data-version-preview-target="iframe"]')
    
    iframes.forEach(iframe => {
      // Get the base preview URL
      const currentSrc = iframe.src
      const url = new URL(currentSrc)
      
      // Update the page parameter
      url.searchParams.set('page', page)
      
      console.log('Updating iframe src to:', url.toString())
      iframe.src = url.toString()
    })
    
    // Also update any mobile navigation current page displays
    const mobilePageNames = document.querySelectorAll('[data-mobile-navigation-target="currentPageName"]')
    mobilePageNames.forEach(element => {
      element.textContent = page
    })
    
    // Broadcast page change event for other components
    const event = new CustomEvent('page-changed', { 
      detail: { page: page, appId: this.appIdValue },
      bubbles: true 
    })
    this.element.dispatchEvent(event)
  }
  
  clickOutside(event) {
    // Close dropdown if clicking outside
    if (!this.element.contains(event.target)) {
      if (this.hasDropdownTarget) {
        this.dropdownTarget.classList.add('hidden')
      }
    }
  }
  
  refreshPreview() {
    console.log('Refreshing preview')
    
    // Find all preview iframes
    const iframes = document.querySelectorAll('[data-preview-device-target="iframe"], [data-version-preview-target="iframe"]')
    
    iframes.forEach(iframe => {
      // Force reload by setting src to itself
      iframe.src = iframe.src
    })
  }
  
  openInNewTab() {
    console.log('Opening preview in new tab')
    
    // Find the preview iframe
    const iframe = document.querySelector('[data-preview-device-target="iframe"], [data-version-preview-target="iframe"]')
    
    if (iframe) {
      window.open(iframe.src, '_blank')
    }
  }
}