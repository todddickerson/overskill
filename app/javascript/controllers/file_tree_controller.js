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
    // Remove previous selection
    this.fileTargets.forEach(file => {
      file.classList.remove('bg-gray-700', 'border-l-2', 'border-primary-500')
    })
    
    // Add selection to clicked file
    const fileElement = event.currentTarget
    fileElement.classList.add('bg-gray-700', 'border-l-2', 'border-primary-500')
  }
  
  organizeFiles() {
    // This would organize files into a tree structure
    // For now, the files are flat, but this could be enhanced
    // to group files by directory
  }
}