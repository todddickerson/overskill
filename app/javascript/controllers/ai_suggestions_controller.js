import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form", "input", "suggestions"]
  
  connect() {
    // Show suggestions after AI completes a task
    if (this.hasSuggestionsTarget) {
      this.showSuggestions()
    }
  }
  
  showSuggestions() {
    // Common follow-up suggestions based on last action
    const suggestions = this.getSuggestionsForContext()
    
    if (suggestions.length > 0) {
      this.suggestionsTarget.innerHTML = this.renderSuggestions(suggestions)
      this.suggestionsTarget.classList.remove("hidden")
    }
  }
  
  getSuggestionsForContext() {
    // Analyze the last AI response to suggest relevant actions
    const lastMessage = document.querySelector('[data-role="assistant"]:last-child')
    if (!lastMessage) return []
    
    const content = lastMessage.textContent.toLowerCase()
    const suggestions = []
    
    // Context-aware suggestions
    if (content.includes("component") || content.includes("created")) {
      suggestions.push({
        text: "Add styling",
        prompt: "Add modern styling with Tailwind CSS classes"
      })
      suggestions.push({
        text: "Make it responsive",
        prompt: "Make the component responsive for mobile devices"
      })
    }
    
    if (content.includes("function") || content.includes("method")) {
      suggestions.push({
        text: "Add error handling",
        prompt: "Add proper error handling and validation"
      })
      suggestions.push({
        text: "Add tests",
        prompt: "Create unit tests for this function"
      })
    }
    
    if (content.includes("api") || content.includes("fetch")) {
      suggestions.push({
        text: "Add loading state",
        prompt: "Add loading indicators while data is being fetched"
      })
      suggestions.push({
        text: "Handle errors",
        prompt: "Add error handling for failed API requests"
      })
    }
    
    // Always available suggestions
    suggestions.push({
      text: "Deploy to production",
      prompt: "Deploy the current version to production"
    })
    
    return suggestions.slice(0, 3) // Limit to 3 suggestions
  }
  
  renderSuggestions(suggestions) {
    return `
      <div class="flex items-center space-x-2 mt-3 pt-3 border-t border-gray-700">
        <span class="text-xs text-gray-500">Suggested:</span>
        ${suggestions.map(s => `
          <button class="text-xs bg-gray-700 hover:bg-gray-600 text-gray-300 px-3 py-1 rounded-full transition-colors"
                  data-action="click->ai-suggestions#useSuggestion"
                  data-suggestion="${s.prompt}">
            ${s.text}
          </button>
        `).join('')}
      </div>
    `
  }
  
  useSuggestion(event) {
    const suggestion = event.currentTarget.dataset.suggestion
    if (this.hasInputTarget) {
      this.inputTarget.value = suggestion
      this.inputTarget.focus()
      
      // Optionally auto-submit
      // this.formTarget.requestSubmit()
    }
  }
}