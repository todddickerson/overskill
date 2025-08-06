import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["folder", "file", "icon", "children"]
  
  connect() {
    this.organizeFiles()
  }
  
  toggleFolder(event) {
    event.preventDefault()
    event.stopPropagation()
    
    const folder = event.currentTarget.closest('[data-file-tree-target="folder"]')
    const children = folder.querySelector('[data-file-tree-target="children"]')
    const icon = folder.querySelector('[data-file-tree-target="icon"]')
    
    if (children) {
      children.classList.toggle('hidden')
      
      // Toggle folder icon
      if (icon) {
        if (children.classList.contains('hidden')) {
          icon.classList.remove('fa-folder-open')
          icon.classList.add('fa-folder')
        } else {
          icon.classList.remove('fa-folder')
          icon.classList.add('fa-folder-open')
        }
      }
    }
  }
  
  selectFile(event) {
    // Don't prevent default - let the link work
    
    // Remove previous selection from all file links
    const allFileLinks = this.element.querySelectorAll('[data-file-tree-target="file"]')
    allFileLinks.forEach(file => {
      file.classList.remove('bg-gray-100', 'dark:bg-gray-800', 'border-l-2', 'border-primary-500')
    })
    
    // Add selection to clicked file
    const fileElement = event.currentTarget
    fileElement.classList.add('bg-gray-100', 'dark:bg-gray-800', 'border-l-2', 'border-primary-500')
  }
  
  navigateToFile(event) {
    const filePath = event.currentTarget.dataset.filePath
    if (!filePath) return
    
    // Find the file in the tree and select it
    const fileLink = this.element.querySelector(`a[href*="${encodeURIComponent(filePath)}"]`)
    if (fileLink) {
      // Remove previous selections
      const allFileLinks = this.element.querySelectorAll('[data-file-tree-target="file"]')
      allFileLinks.forEach(file => {
        file.classList.remove('bg-gray-100', 'dark:bg-gray-800', 'border-l-2', 'border-primary-500')
      })
      
      // Add selection to the target file
      fileLink.classList.add('bg-gray-100', 'dark:bg-gray-800', 'border-l-2', 'border-primary-500')
      
      // Scroll to the file in the tree
      fileLink.scrollIntoView({ behavior: 'smooth', block: 'center' })
      
      // Navigate to the file (trigger the link click)
      fileLink.click()
      
      // Switch to Files tab if we're not already there
      this.switchToFilesTab()
    } else {
      console.warn('File not found in tree:', filePath)
    }
  }
  
  switchToFilesTab() {
    // Find and activate the Files tab
    const filesTab = document.querySelector('[data-main-tabs-target="tab"][data-tab="files"]')
    if (filesTab && !filesTab.classList.contains('active')) {
      filesTab.click()
    }
  }
  
  organizeFiles() {
    // This would organize files into a tree structure
    // For now, the files are flat, but this could be enhanced
    // to group files by directory
  }
}