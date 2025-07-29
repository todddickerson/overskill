import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.resize()
  }

  resize() {
    this.element.style.height = 'auto'
    this.element.style.height = this.element.scrollHeight + 'px'
  }

  submit(event) {
    if (event.key === 'Enter' && (event.metaKey || event.ctrlKey)) {
      event.preventDefault()
      this.element.form.requestSubmit()
    }
  }
}