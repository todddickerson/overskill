import { Controller } from "@hotwired/stimulus"
import { EditorView, basicSetup } from "codemirror"
import { EditorState } from "@codemirror/state"
import { oneDark } from "@codemirror/theme-one-dark"
import { javascript } from "@codemirror/lang-javascript"
import { css } from "@codemirror/lang-css"
import { html } from "@codemirror/lang-html"
import { json } from "@codemirror/lang-json"

export default class extends Controller {
  static targets = ["editor", "status", "line", "column", "fallback"]
  static values = { 
    content: String, 
    fileType: String,
    fileId: String,
    updateUrl: String
  }
  
  initialize() {
    this.connectDebounce = null
  }

  connect() {
    console.log('[CodeMirror] Controller connecting...')
    
    // Clear any pending connection
    if (this.connectDebounce) {
      clearTimeout(this.connectDebounce)
    }
    
    // Debounce the actual connection to prevent rapid reconnections
    this.connectDebounce = setTimeout(() => {
      console.log('[CodeMirror] Targets:', {
        hasEditor: this.hasEditorTarget,
        hasStatus: this.hasStatusTarget,
        editorTarget: this.editorTarget
      })
      console.log('[CodeMirror] Values:', {
        content: this.contentValue?.substring(0, 50) + '...',
        fileType: this.fileTypeValue,
        fileId: this.fileIdValue
      })
      
      // Prevent multiple initializations
      if (this.editor) {
        console.log('[CodeMirror] Editor already exists, destroying old instance')
        this.editor.destroy()
        this.editor = null
      }
      
      try {
        this.setupEditor()
        this.updateTimer = null
        console.log('[CodeMirror] Controller connected successfully')
      } catch (error) {
        console.error('[CodeMirror] Failed to connect:', error)
        console.error('[CodeMirror] Error stack:', error.stack)
        this.showFallbackEditor()
      }
    }, 100) // Small delay to batch rapid reconnections
  }

  disconnect() {
    if (this.connectDebounce) {
      clearTimeout(this.connectDebounce)
    }
    if (this.editor) {
      this.editor.destroy()
      this.editor = null
    }
    if (this.updateTimer) {
      clearTimeout(this.updateTimer)
    }
  }

  contentValueChanged() {
    // Re-initialize editor when content changes (switching files)
    if (this.editor) {
      this.editor.destroy()
    }
    this.setupEditor()
  }

  setupEditor() {
    console.log('[CodeMirror] Setting up editor...')
    try {
      // Ensure the editor target has proper dimensions
      const editorHeight = this.editorTarget.offsetHeight
      console.log('[CodeMirror] Editor target height:', editorHeight)
      
      if (editorHeight === 0) {
        console.warn('[CodeMirror] Editor target has no height, setting minimum height')
        this.editorTarget.style.minHeight = '400px'
      }
      
      const extensions = [
        basicSetup,
        oneDark,
        this.getLanguageExtension(),
        EditorView.updateListener.of((update) => {
          if (update.docChanged) {
            this.handleChange()
          }
          this.updateCursorPosition(update)
        }),
        EditorView.theme({
          "&": {
            height: "100%"
          },
          ".cm-editor": {
            height: "100%"
          },
          ".cm-scroller": {
            fontFamily: "ui-monospace, SFMono-Regular, Consolas, 'Liberation Mono', Menlo, monospace",
            overflow: "auto"
          },
          ".cm-content": {
            minHeight: "100%"
          }
        })
      ]

      const state = EditorState.create({
        doc: this.contentValue,
        extensions
      })

      this.editor = new EditorView({
        state,
        parent: this.editorTarget
      })

      // Hide the original textarea
      const textarea = this.element.querySelector('textarea')
      if (textarea) {
        textarea.style.display = 'none'
      }
      
      console.log('[CodeMirror] Editor setup complete')
    } catch (error) {
      console.error('[CodeMirror] Failed to setup editor:', error)
      this.showFallbackEditor()
    }
  }
  
  showFallbackEditor() {
    console.log('[CodeMirror] Showing fallback textarea editor')
    const textarea = this.element.querySelector('textarea')
    if (textarea) {
      textarea.style.display = 'block'
      textarea.style.position = 'static'
      // Make it work with the simple code editor controller as fallback
      textarea.setAttribute('data-controller', 'code-editor')
      textarea.setAttribute('data-code-editor-target', 'editor')
      textarea.setAttribute('data-file-id', this.fileIdValue)
      
      if (this.statusTarget) {
        this.statusTarget.textContent = 'CodeMirror failed - using fallback editor'
      }
    }
  }

  getLanguageExtension() {
    switch (this.fileTypeValue) {
      case "javascript":
        return javascript()
      case "css":
        return css()
      case "html":
        return html()
      case "json":
        return json()
      default:
        return []
    }
  }

  handleChange() {
    if (this.statusTarget) {
      this.statusTarget.textContent = "Modified"
    }

    // Debounce the save operation
    if (this.updateTimer) {
      clearTimeout(this.updateTimer)
    }

    this.updateTimer = setTimeout(() => {
      this.saveFile()
    }, 2000) // Save after 2 seconds of inactivity
  }

  updateCursorPosition(update) {
    if (update.selectionSet && this.lineTarget && this.columnTarget) {
      const cursor = update.state.selection.main.head
      const line = update.state.doc.lineAt(cursor)
      this.lineTarget.textContent = line.number
      this.columnTarget.textContent = cursor - line.from + 1
    }
  }

  async saveFile() {
    if (!this.updateUrlValue || !this.editor) return

    const content = this.editor.state.doc.toString()
    
    try {
      if (this.statusTarget) {
        this.statusTarget.textContent = "Saving..."
      }

      const response = await fetch(this.updateUrlValue, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
        },
        body: JSON.stringify({
          app_file: {
            content: content
          }
        })
      })

      if (response.ok) {
        if (this.statusTarget) {
          this.statusTarget.textContent = "Saved"
          setTimeout(() => {
            if (this.statusTarget) {
              this.statusTarget.textContent = "Ready"
            }
          }, 2000)
        }
      } else {
        throw new Error('Save failed')
      }
    } catch (error) {
      console.error('Failed to save file:', error)
      if (this.statusTarget) {
        this.statusTarget.textContent = "Save failed"
      }
    }
  }

  // Manual save trigger (for Cmd+S or Ctrl+S)
  forceSave() {
    if (this.updateTimer) {
      clearTimeout(this.updateTimer)
    }
    this.saveFile()
  }
}