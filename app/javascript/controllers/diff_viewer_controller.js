import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["diff"]
  
  toggleDiff(event) {
    const fileId = event.params.file
    const diffElement = this.diffTargets.find(el => el.dataset.fileId === fileId.toString())
    
    if (diffElement) {
      diffElement.classList.toggle("hidden")
      
      // Update chevron icon
      const button = event.currentTarget
      const icon = button.querySelector("i")
      if (icon) {
        icon.classList.toggle("fa-chevron-down")
        icon.classList.toggle("fa-chevron-up")
      }
    }
  }
}