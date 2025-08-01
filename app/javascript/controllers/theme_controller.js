import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.applySystemTheme()
    this.watchSystemTheme()
  }
  
  disconnect() {
    if (this.mediaQuery) {
      this.mediaQuery.removeEventListener('change', this.handleThemeChange.bind(this))
    }
  }
  
  applySystemTheme() {
    const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches
    this.setTheme(prefersDark ? 'dark' : 'light')
  }
  
  watchSystemTheme() {
    this.mediaQuery = window.matchMedia('(prefers-color-scheme: dark)')
    this.mediaQuery.addEventListener('change', this.handleThemeChange.bind(this))
  }
  
  handleThemeChange(e) {
    this.setTheme(e.matches ? 'dark' : 'light')
  }
  
  setTheme(theme) {
    const html = document.documentElement
    
    if (theme === 'dark') {
      html.classList.add('dark')
    } else {
      html.classList.remove('dark')
    }
    
    // Store preference for consistency
    localStorage.setItem('theme-preference', theme)
  }
}