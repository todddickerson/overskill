import { Controller } from "@hotwired/stimulus"

// Controller to handle device preview switching (desktop/mobile)
export default class extends Controller {
  static targets = ["desktopButton", "mobileButton", "container", "iframe"]
  static values = { currentDevice: String }
  
  connect() {
    this.updateDeviceView()
  }
  
  setDesktop() {
    this.currentDeviceValue = 'desktop'
    this.updateDeviceView()
  }
  
  setMobile() {
    this.currentDeviceValue = 'mobile'
    this.updateDeviceView()
  }
  
  updateDeviceView() {
    // Update button states
    if (this.currentDeviceValue === 'desktop') {
      this.desktopButtonTarget.classList.remove('text-gray-500', 'dark:text-gray-400')
      this.desktopButtonTarget.classList.add('bg-white', 'dark:bg-gray-600', 'text-gray-700', 'dark:text-gray-300', 'shadow-sm')
      
      this.mobileButtonTarget.classList.remove('bg-white', 'dark:bg-gray-600', 'text-gray-700', 'dark:text-gray-300', 'shadow-sm')
      this.mobileButtonTarget.classList.add('text-gray-500', 'dark:text-gray-400')
      
      // Desktop view - full width
      this.containerTarget.classList.remove('max-w-sm', 'mx-auto')
      this.containerTarget.style.maxWidth = ''
    } else {
      this.mobileButtonTarget.classList.remove('text-gray-500', 'dark:text-gray-400')
      this.mobileButtonTarget.classList.add('bg-white', 'dark:bg-gray-600', 'text-gray-700', 'dark:text-gray-300', 'shadow-sm')
      
      this.desktopButtonTarget.classList.remove('bg-white', 'dark:bg-gray-600', 'text-gray-700', 'dark:text-gray-300', 'shadow-sm')
      this.desktopButtonTarget.classList.add('text-gray-500', 'dark:text-gray-400')
      
      // Mobile view - constrained width
      this.containerTarget.classList.add('max-w-sm', 'mx-auto')
      this.containerTarget.style.maxWidth = '375px'
    }
  }
}