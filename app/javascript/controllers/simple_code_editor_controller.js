import { Controller } from "@hotwired/stimulus"

// Simple fallback code editor when CodeMirror fails
export default class extends Controller {
  static targets = ["editor", "status"]
  static values = { 
    fileId: String,
    updateUrl: String
  }
  
  connect() {
    console.log('[SimpleCodeEditor] Connected as fallback editor')
    this.setupEditor()
    this.saveTimer = null
  }
  
  disconnect() {
    if (this.saveTimer) {
      clearTimeout(this.saveTimer)
    }
  }
  
  setupEditor() {
    if (!this.hasEditorTarget) return
    
    // Setup basic textarea styling
    this.editorTarget.style.fontFamily = "ui-monospace, SFMono-Regular, Consolas, 'Liberation Mono', Menlo, monospace"
    this.editorTarget.style.fontSize = "14px"
    this.editorTarget.style.lineHeight = "1.5"
    this.editorTarget.style.padding = "1rem"
    this.editorTarget.style.width = "100%"
    this.editorTarget.style.height = "100%"
    this.editorTarget.style.minHeight = "400px"
    this.editorTarget.style.resize = "none"
    this.editorTarget.style.border = "none"
    this.editorTarget.style.outline = "none"
    this.editorTarget.style.backgroundColor = "#282c34"
    this.editorTarget.style.color = "#abb2bf"
    
    // Add tab support
    this.editorTarget.addEventListener('keydown', this.handleTab.bind(this))
    
    // Add auto-save on change
    this.editorTarget.addEventListener('input', this.handleChange.bind(this))
    
    if (this.hasStatusTarget) {
      this.statusTarget.textContent = 'Simple editor ready'
    }
  }
  
  handleTab(event) {
    if (event.key === 'Tab') {
      event.preventDefault()
      const start = this.editorTarget.selectionStart
      const end = this.editorTarget.selectionEnd
      const value = this.editorTarget.value
      
      // Insert 2 spaces for tab
      this.editorTarget.value = value.substring(0, start) + '  ' + value.substring(end)
      
      // Move cursor after the inserted spaces
      this.editorTarget.selectionStart = this.editorTarget.selectionEnd = start + 2
    }
  }
  
  handleChange() {
    if (this.hasStatusTarget) {
      this.statusTarget.textContent = 'Modified'
    }
    
    // Clear existing timer
    if (this.saveTimer) {
      clearTimeout(this.saveTimer)
    }
    
    // Set new timer for auto-save
    this.saveTimer = setTimeout(() => {
      this.saveContent()
    }, 1000) // Save after 1 second of inactivity
  }
  
  async saveContent() {
    if (!this.updateUrlValue || !this.fileIdValue) {
      console.log('[SimpleCodeEditor] Missing update URL or file ID')
      return
    }
    
    const content = this.editorTarget.value
    
    if (this.hasStatusTarget) {
      this.statusTarget.textContent = 'Saving...'
    }
    
    try {
      const response = await fetch(this.updateUrlValue.replace(':id', this.fileIdValue), {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
          'Accept': 'application/json'
        },
        body: JSON.stringify({
          app_file: { content: content }
        })
      })
      
      if (response.ok) {
        if (this.hasStatusTarget) {
          this.statusTarget.textContent = 'Saved'
        }
        
        // Dispatch custom event for other components
        this.dispatch('saved', { detail: { fileId: this.fileIdValue } })
      } else {
        throw new Error('Save failed')
      }
    } catch (error) {
      console.error('[SimpleCodeEditor] Save error:', error)
      if (this.hasStatusTarget) {
        this.statusTarget.textContent = 'Save failed'
      }
    }
  }
  
  // Manual save method
  save() {
    this.saveContent()
  }
}