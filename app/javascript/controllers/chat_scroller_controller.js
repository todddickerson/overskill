import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.scrollToBottom()
  }

  scrollToBottom() {
    const container = this.element
    container.scrollTop = container.scrollHeight
  }

  // Call this when new messages are added
  messageAdded() {
    this.scrollToBottom()
  }
}