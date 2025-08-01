import { Controller } from "@hotwired/stimulus"

// Debug version to help diagnose tab switching issues
export default class extends Controller {
  static targets = ["tab", "panel"]

  connect() {
    console.log("🐛 DEBUG: Tabs controller connected!")
    console.log("Element with controller:", this.element)
    console.log("Number of tabs found:", this.tabTargets.length)
    console.log("Number of panels found:", this.panelTargets.length)
    
    // List all tabs
    console.log("Tabs:")
    this.tabTargets.forEach((tab, i) => {
      console.log(`  ${i}: data-panel="${tab.dataset.panel}"`, tab)
    })
    
    // List all panels
    console.log("Panels:")
    this.panelTargets.forEach((panel, i) => {
      console.log(`  ${i}: data-panel-name="${panel.dataset.panelName}", hidden=${panel.classList.contains('hidden')}`, panel)
    })
    
    // Check if we have matching tabs and panels
    const tabNames = this.tabTargets.map(t => t.dataset.panel)
    const panelNames = this.panelTargets.map(p => p.dataset.panelName)
    console.log("Tab names:", tabNames)
    console.log("Panel names:", panelNames)
    
    // Initialize with first tab or URL param
    const urlParams = new URLSearchParams(window.location.search)
    const activeTab = urlParams.get('tab') || 'preview'
    console.log(`Initializing with tab: ${activeTab}`)
    this.showPanel(activeTab)
  }

  switchTab(event) {
    event.preventDefault()
    const panel = event.currentTarget.dataset.panel
    console.log(`🐛 Tab clicked: ${panel}`)
    this.showPanel(panel)
  }

  showPanel(panelName) {
    console.log(`🐛 showPanel called with: ${panelName}`)
    
    // Update tabs
    this.tabTargets.forEach((tab) => {
      const tabPanel = tab.dataset.panel
      const isActive = tabPanel === panelName
      
      console.log(`  Tab ${tabPanel}: active=${isActive}`)
      
      if (isActive) {
        tab.classList.remove("text-gray-400", "border-transparent")
        tab.classList.add("text-white", "border-primary-500")
      } else {
        tab.classList.remove("text-white", "border-primary-500")
        tab.classList.add("text-gray-400", "border-transparent")
      }
    })

    // Update panels
    this.panelTargets.forEach((panel) => {
      const panelDataName = panel.dataset.panelName
      const shouldShow = panelDataName === panelName
      
      console.log(`  Panel ${panelDataName}: shouldShow=${shouldShow}, currentlyHidden=${panel.classList.contains('hidden')}`)
      
      if (shouldShow) {
        panel.classList.remove("hidden")
        console.log(`    ✅ Removed hidden class`)
      } else {
        panel.classList.add("hidden")
        console.log(`    ➕ Added hidden class`)
      }
    })
    
    // Verify final state
    console.log("🐛 Final panel visibility:")
    this.panelTargets.forEach(panel => {
      console.log(`  ${panel.dataset.panelName}: ${panel.classList.contains('hidden') ? 'HIDDEN' : 'VISIBLE'}`)
    })
    
    // Update URL
    const url = new URL(window.location)
    url.searchParams.set('tab', panelName)
    window.history.replaceState({}, '', url)
  }
}