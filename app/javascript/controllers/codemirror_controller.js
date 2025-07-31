import { Controller } from "@hotwired/stimulus"
import { EditorView, basicSetup } from "codemirror"
import { EditorState } from "@codemirror/state"
import { oneDark } from "@codemirror/theme-one-dark"
import { javascript } from "@codemirror/lang-javascript"
import { css } from "@codemirror/lang-css"
import { html } from "@codemirror/lang-html"
import { json } from "@codemirror/lang-json"

export default class extends Controller {
  static targets = ["editor", "status", "line", "column"]
  static values = { 
    content: String, 
    fileType: String,
    fileId: String,
    updateUrl: String
  }

  connect() {
    this.setupEditor()
    this.updateTimer = null
  }

  disconnect() {
    if (this.editor) {
      this.editor.destroy()
    }
    if (this.updateTimer) {
      clearTimeout(this.updateTimer)
    }
  }

  setupEditor() {
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
        ".cm-scroller": {
          fontFamily: "ui-monospace, SFMono-Regular, Consolas, 'Liberation Mono', Menlo, monospace"
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