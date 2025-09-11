import { Controller } from "@hotwired/stimulus"
import consumer from "../channels/consumer"

// Connects to data-controller="hmr"
export default class extends Controller {
  static values = { appId: String }
  
  connect() {
    console.log(`[HMR] Initializing for app ${this.appIdValue}`)
    
    if (!window.HMR_ENABLED) {
      console.log("[HMR] HMR is not enabled for this environment")
      return
    }
    
    this.setupActionCableSubscription()
    this.setupIframeMessageHandler()
  }
  
  disconnect() {
    if (this.subscription) {
      this.subscription.unsubscribe()
      console.log(`[HMR] Unsubscribed from app ${this.appIdValue}`)
    }
    
    if (this.messageHandler) {
      window.removeEventListener("message", this.messageHandler)
    }
  }
  
  setupActionCableSubscription() {
    // Subscribe to the AppPreviewChannel for this app
    this.subscription = consumer.subscriptions.create(
      { 
        channel: "AppPreviewChannel", 
        app_id: this.appIdValue 
      },
      {
        connected: () => {
          console.log(`[HMR] Connected to AppPreviewChannel for app ${this.appIdValue}`)
        },
        
        disconnected: () => {
          console.log(`[HMR] Disconnected from AppPreviewChannel`)
        },
        
        received: (data) => {
          console.log("[HMR] Received update:", data)
          
          if (data.type === "hmr_update") {
            this.applyHMRUpdate(data)
          } else if (data.type === "full_reload") {
            this.reloadPreview()
          } else if (data.type === "error") {
            this.showError(data.error)
          }
        },
        
        // Custom action for updating files
        update_file: function(data) {
          return this.perform("update_file", data)
        },
        
        // Custom action for Puck saves
        save_puck: function(data) {
          return this.perform("save_puck", data)
        }
      }
    )
  }
  
  setupIframeMessageHandler() {
    // Listen for messages from the preview iframe
    this.messageHandler = (event) => {
      // Verify origin matches our preview URL
      if (!window.PREVIEW_URL || !event.origin.startsWith(window.PREVIEW_URL.split('/').slice(0, 3).join('/'))) {
        return
      }
      
      const { type, payload } = event.data || {}
      
      switch(type) {
        case "hmr_ready":
          console.log("[HMR] Preview iframe is ready for HMR")
          break
          
        case "request_update":
          // Preview is requesting an update for a specific file
          this.requestFileUpdate(payload.path)
          break
          
        case "error":
          console.error("[HMR] Error from preview:", payload)
          break
      }
    }
    
    window.addEventListener("message", this.messageHandler)
  }
  
  applyHMRUpdate(data) {
    const iframe = this.element.querySelector("iframe")
    if (!iframe) {
      console.warn("[HMR] No iframe found to apply update")
      return
    }
    
    // Send HMR update to the iframe
    iframe.contentWindow.postMessage({
      type: "hmr_update",
      path: data.path,
      content: data.content,
      compiled: data.compiled_content,
      timestamp: data.timestamp
    }, "*")
    
    console.log(`[HMR] Applied update to ${data.path}`)
  }
  
  reloadPreview() {
    const iframe = this.element.querySelector("iframe")
    if (iframe) {
      console.log("[HMR] Reloading preview iframe")
      iframe.src = iframe.src
    }
  }
  
  showError(error) {
    console.error("[HMR] Error:", error)
    
    // Send error to iframe for display
    const iframe = this.element.querySelector("iframe")
    if (iframe) {
      iframe.contentWindow.postMessage({
        type: "hmr_error",
        error: error
      }, "*")
    }
  }
  
  requestFileUpdate(path) {
    // Request file update through ActionCable
    if (this.subscription) {
      this.subscription.update_file({ path: path })
    }
  }
  
  // Public method that can be called from other controllers
  updateFile(path, content) {
    if (this.subscription) {
      return this.subscription.update_file({ 
        path: path, 
        content: content 
      })
    }
  }
  
  // Public method for Puck saves
  savePuckData(puckData) {
    if (this.subscription) {
      return this.subscription.save_puck({ 
        puck_data: puckData 
      })
    }
  }
}