import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "panel"]

  connect() {
    console.log("🎯 Tabs controller connected!")
    console.log("Controller element:", this.element)
    console.log("Found tabs:", this.tabTargets.length)
    console.log("Found panels:", this.panelTargets.length)
    
    // Add visible indication that controller is connected
    this.element.style.border = "2px solid red"
    setTimeout(() => {
      this.element.style.border = ""
    }, 1000)
    
    // Log details about each panel
    this.panelTargets.forEach((panel, index) => {
      console.log(`Panel ${index}:`, {
        panelName: panel.dataset.panelName,
        classes: panel.className,
        hidden: panel.classList.contains("hidden"),
        element: panel
      })
    })
    
    // Show the first tab by default
    this.showPanel("preview")
  }

  disconnect() {
    console.log("🔌 Tabs controller disconnected!")
  }

  switchTab(event) {
    console.log("🖱️ Tab clicked:", event.currentTarget)
    event.preventDefault()
    const panel = event.currentTarget.dataset.panel
    console.log("Requested panel:", panel)
    this.showPanel(panel)
  }

  showPanel(panelName) {
    console.log("📋 showPanel called with:", panelName)
    console.log("Panel targets count:", this.panelTargets.length)
    console.log("Tab targets count:", this.tabTargets.length)
    
    // Update tabs
    this.tabTargets.forEach((tab, index) => {
      const tabPanel = tab.dataset.panel
      console.log(`Tab ${index} (${tabPanel}):`, {
        isActive: tabPanel === panelName,
        element: tab
      })
      
      if (tabPanel === panelName) {
        tab.classList.remove("text-gray-400", "border-transparent")
        tab.classList.add("text-white", "border-primary-500")
      } else {
        tab.classList.remove("text-white", "border-primary-500")
        tab.classList.add("text-gray-400", "border-transparent")
      }
    })

    // Update panels
    this.panelTargets.forEach((panel, index) => {
      const panelDataName = panel.dataset.panelName
      const shouldShow = panelDataName === panelName
      
      console.log(`Panel ${index} (${panelDataName}):`, {
        shouldShow,
        currentlyHidden: panel.classList.contains("hidden"),
        willBeHidden: !shouldShow,
        classList: Array.from(panel.classList),
        element: panel
      })
      
      if (shouldShow) {
        console.log(`✅ Showing panel: ${panelDataName}`)
        panel.classList.remove("hidden")
      } else {
        console.log(`❌ Hiding panel: ${panelDataName}`)
        panel.classList.add("hidden")
      }
    })
    
    // Verify final state
    console.log("🔍 Final panel states:")
    this.panelTargets.forEach(panel => {
      console.log(`- ${panel.dataset.panelName}: ${panel.classList.contains("hidden") ? "HIDDEN" : "VISIBLE"}`)
    })
  }
}