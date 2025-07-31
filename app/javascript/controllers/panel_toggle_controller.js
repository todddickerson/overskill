import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["label"]
  
  connect() {
    this.filesPanel = document.querySelector('[data-panel-name="files-sidebar"]')
    this.updateLabel()
  }
  
  toggle(event) {
    event.preventDefault()
    
    if (this.filesPanel) {
      this.filesPanel.classList.toggle("hidden")
      this.updateLabel()
    }
  }
  
  updateLabel() {
    if (this.hasLabelTarget && this.filesPanel) {
      this.labelTarget.textContent = this.filesPanel.classList.contains("hidden") ? "Show Files" : "Hide Files"
    }
  }
}