import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["editor", "status", "line", "column"]
  
  connect() {
    this.saveTimeout = null
    this.originalContent = this.editorTarget.value
    
    // Update cursor position
    this.editorTarget.addEventListener('click', () => this.updateCursorPosition())
    this.editorTarget.addEventListener('keyup', () => this.updateCursorPosition())
    
    // Add tab support
    this.editorTarget.addEventListener('keydown', (e) => {
      if (e.key === 'Tab') {
        e.preventDefault()
        const start = this.editorTarget.selectionStart
        const end = this.editorTarget.selectionEnd
        
        this.editorTarget.value = this.editorTarget.value.substring(0, start) + '  ' + this.editorTarget.value.substring(end)
        this.editorTarget.selectionStart = this.editorTarget.selectionEnd = start + 2
      }
    })
  }
  
  handleChange() {
    // Clear existing timeout
    if (this.saveTimeout) {
      clearTimeout(this.saveTimeout)
    }
    
    // Show unsaved indicator
    this.statusTarget.textContent = "Modified"
    this.statusTarget.classList.add("text-yellow-400")
    
    // Auto-save after 1 second of inactivity
    this.saveTimeout = setTimeout(() => {
      this.save()
    }, 1000)
  }
  
  async save() {
    const fileId = this.element.dataset.fileId
    const content = this.editorTarget.value
    
    // Don't save if content hasn't changed
    if (content === this.originalContent) {
      this.statusTarget.textContent = "Ready"
      this.statusTarget.classList.remove("text-yellow-400")
      return
    }
    
    this.statusTarget.textContent = "Saving..."
    
    try {
      const response = await fetch(`/account/apps/${this.getAppId()}/editor/files/${fileId}`, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
        },
        body: JSON.stringify({ content })
      })
      
      if (response.ok) {
        this.originalContent = content
        this.statusTarget.textContent = "Saved"
        this.statusTarget.classList.remove("text-yellow-400")
        this.statusTarget.classList.add("text-green-400")
        
        setTimeout(() => {
          this.statusTarget.textContent = "Ready"
          this.statusTarget.classList.remove("text-green-400")
        }, 2000)
      } else {
        this.statusTarget.textContent = "Error saving"
        this.statusTarget.classList.add("text-red-400")
      }
    } catch (error) {
      this.statusTarget.textContent = "Error saving"
      this.statusTarget.classList.add("text-red-400")
    }
  }
  
  updateCursorPosition() {
    const textarea = this.editorTarget
    const text = textarea.value.substring(0, textarea.selectionStart)
    const lines = text.split('\n')
    const line = lines.length
    const column = lines[lines.length - 1].length + 1
    
    this.lineTarget.textContent = line
    this.columnTarget.textContent = column
  }
  
  getAppId() {
    // Extract app ID from the URL
    const match = window.location.pathname.match(/apps\/(\d+)/)
    return match ? match[1] : null
  }
}