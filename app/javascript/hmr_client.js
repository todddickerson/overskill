// HMR Client - WebSocket client for hot module replacement via ActionCable
// Handles real-time code updates without page refresh
// Part of the Fast Deployment Architecture for instant preview updates

import consumer from "./channels/consumer";

class HMRClient {
  constructor(appId) {
    this.appId = appId;
    this.subscription = null;
    this.moduleCache = new Map();
    this.updateQueue = [];
    this.isUpdating = false;
  }

  connect() {
    console.log('[HMR] Connecting to preview channel...');
    
    this.subscription = consumer.subscriptions.create(
      { 
        channel: "AppPreviewChannel",
        app_id: this.appId
      },
      {
        connected: () => {
          console.log('[HMR] Connected to preview channel');
          this.onConnected();
        },

        disconnected: () => {
          console.log('[HMR] Disconnected from preview channel');
          this.onDisconnected();
        },

        received: (data) => {
          this.handleMessage(data);
        }
      }
    );
  }

  handleMessage(data) {
    console.log('[HMR] Received message:', data.type);
    
    switch(data.type) {
      case 'connected':
        this.sessionId = data.session_id;
        this.enableHMR();
        break;
        
      case 'hmr_update':
        this.applyHMRUpdate(data.path, data.content);
        break;
        
      case 'hmr_batch':
        this.applyBatchUpdate(data.files);
        break;
        
      case 'hmr_component':
        this.hotReloadComponent(data.component, data.code, data.source_map);
        break;
        
      case 'build_error':
        this.showBuildError(data.path, data.error);
        break;
        
      case 'preview_refreshed':
        this.handlePreviewRefresh(data);
        break;
        
      default:
        console.log('[HMR] Unknown message type:', data.type);
    }
  }

  applyHMRUpdate(path, content) {
    console.log(`[HMR] Applying update to ${path}`);
    
    // Queue update to prevent race conditions
    this.updateQueue.push({ path, content });
    
    if (!this.isUpdating) {
      this.processUpdateQueue();
    }
  }

  async processUpdateQueue() {
    this.isUpdating = true;
    
    while (this.updateQueue.length > 0) {
      const { path, content } = this.updateQueue.shift();
      
      try {
        if (path.endsWith('.css')) {
          this.updateStyles(path, content);
        } else if (path.endsWith('.tsx') || path.endsWith('.jsx')) {
          await this.updateComponent(path, content);
        } else {
          await this.updateModule(path, content);
        }
        
        console.log(`[HMR] ✓ Updated ${path}`);
      } catch (error) {
        console.error(`[HMR] Failed to update ${path}:`, error);
        this.showUpdateError(path, error);
      }
    }
    
    this.isUpdating = false;
  }

  updateStyles(path, content) {
    // Find or create style element
    let styleEl = document.querySelector(`style[data-hmr-path="${path}"]`);
    
    if (!styleEl) {
      styleEl = document.createElement('style');
      styleEl.setAttribute('data-hmr-path', path);
      document.head.appendChild(styleEl);
    }
    
    styleEl.textContent = content;
  }

  async updateComponent(path, content) {
    // Create a blob URL for the new module
    const blob = new Blob([content], { type: 'application/javascript' });
    const blobUrl = URL.createObjectURL(blob);
    
    try {
      // Dynamically import the new module
      const newModule = await import(blobUrl);
      
      // Store in cache for future reference
      this.moduleCache.set(path, newModule);
      
      // Trigger React Fast Refresh if available
      if (window.$RefreshReg$ && window.$RefreshSig$) {
        window.$RefreshReg$(newModule.default, path);
        window.$RefreshRuntime$.performReactRefresh();
      } else {
        // Fall back to component re-render
        this.rerenderComponent(path, newModule);
      }
    } finally {
      // Clean up blob URL
      URL.revokeObjectURL(blobUrl);
    }
  }

  async updateModule(path, content) {
    // For non-component modules, create and evaluate
    const moduleWrapper = `
      (function() {
        const module = { exports: {} };
        const exports = module.exports;
        ${content}
        return module.exports;
      })()
    `;
    
    try {
      const moduleExports = eval(moduleWrapper);
      this.moduleCache.set(path, moduleExports);
      
      // Notify dependent modules
      this.invalidateDependents(path);
    } catch (error) {
      console.error(`[HMR] Failed to evaluate module ${path}:`, error);
      throw error;
    }
  }

  hotReloadComponent(componentName, code, sourceMap) {
    console.log(`[HMR] Hot reloading component: ${componentName}`);
    
    // Apply source map for debugging
    if (sourceMap) {
      this.applySourceMap(componentName, sourceMap);
    }
    
    // Create component module
    const componentPath = `src/components/${componentName}.tsx`;
    this.updateComponent(componentPath, code);
  }

  applyBatchUpdate(files) {
    console.log(`[HMR] Applying batch update for ${Object.keys(files).length} files`);
    
    // Sort files by dependency order
    const sortedPaths = this.sortByDependencyOrder(Object.keys(files));
    
    // Apply updates in order
    sortedPaths.forEach(path => {
      this.applyHMRUpdate(path, files[path]);
    });
  }

  rerenderComponent(path, module) {
    // Find all mounted instances of this component
    const componentName = this.getComponentName(path);
    const mountPoints = document.querySelectorAll(`[data-react-component="${componentName}"]`);
    
    mountPoints.forEach(mountPoint => {
      // Re-render using React 18 API
      const root = window.__reactRoots?.get(mountPoint);
      if (root && module.default) {
        root.render(React.createElement(module.default));
      }
    });
  }

  invalidateDependents(modulePath) {
    // Find and update modules that depend on this one
    // This would integrate with your module dependency graph
    console.log(`[HMR] Invalidating dependents of ${modulePath}`);
  }

  sortByDependencyOrder(paths) {
    // Sort paths so dependencies are updated before dependents
    // For now, just ensure CSS comes before JS
    return paths.sort((a, b) => {
      if (a.endsWith('.css') && !b.endsWith('.css')) return -1;
      if (!a.endsWith('.css') && b.endsWith('.css')) return 1;
      return 0;
    });
  }

  getComponentName(path) {
    // Extract component name from path
    const match = path.match(/\/([^/]+)\.(tsx|jsx)$/);
    return match ? match[1] : 'Unknown';
  }

  applySourceMap(name, sourceMap) {
    // Register source map for better debugging
    const blob = new Blob([sourceMap], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    
    // Add source mapping comment to enable browser devtools mapping
    const script = document.createElement('script');
    script.textContent = `//# sourceMappingURL=${url}`;
    script.setAttribute('data-hmr-sourcemap', name);
    document.head.appendChild(script);
  }

  showBuildError(path, error) {
    // Show build error overlay
    const overlay = this.createErrorOverlay();
    overlay.innerHTML = `
      <div class="hmr-error">
        <h3>Build Error</h3>
        <p class="hmr-error-file">${path}</p>
        <pre class="hmr-error-message">${this.escapeHtml(error)}</pre>
        <button onclick="this.parentElement.parentElement.remove()">Dismiss</button>
      </div>
    `;
    document.body.appendChild(overlay);
  }

  showUpdateError(path, error) {
    console.error(`[HMR] Update failed for ${path}:`, error);
    
    // Show less intrusive error notification
    const notification = this.createNotification();
    notification.textContent = `HMR update failed for ${path}`;
    notification.classList.add('hmr-error-notification');
    
    setTimeout(() => notification.remove(), 5000);
  }

  createErrorOverlay() {
    const overlay = document.createElement('div');
    overlay.className = 'hmr-error-overlay';
    overlay.style.cssText = `
      position: fixed;
      top: 0;
      left: 0;
      right: 0;
      bottom: 0;
      background: rgba(0,0,0,0.85);
      color: white;
      padding: 20px;
      z-index: 999999;
      font-family: monospace;
      overflow: auto;
    `;
    return overlay;
  }

  createNotification() {
    const notification = document.createElement('div');
    notification.style.cssText = `
      position: fixed;
      bottom: 20px;
      right: 20px;
      background: #ff4444;
      color: white;
      padding: 12px 20px;
      border-radius: 4px;
      z-index: 999998;
      font-family: system-ui;
      box-shadow: 0 2px 8px rgba(0,0,0,0.3);
    `;
    document.body.appendChild(notification);
    return notification;
  }

  enableHMR() {
    // Setup React Fast Refresh if not already enabled
    if (!window.$RefreshReg$) {
      this.setupReactRefresh();
    }
    
    // Monitor for file changes in development
    if (process.env.NODE_ENV === 'development') {
      this.setupFileWatcher();
    }
  }

  setupReactRefresh() {
    // Initialize React Fast Refresh runtime
    const script = document.createElement('script');
    script.src = '/@react-refresh';
    script.onload = () => {
      window.$RefreshRuntime$.injectIntoGlobalHook(window);
      window.$RefreshReg$ = () => {};
      window.$RefreshSig$ = () => (type) => type;
    };
    document.head.appendChild(script);
  }

  setupFileWatcher() {
    // Setup file watching for local development
    // This would integrate with your build system
    console.log('[HMR] File watcher enabled');
  }

  handlePreviewRefresh(data) {
    console.log('[HMR] Preview refreshed:', data.url);
    
    // Update iframe if in editor view
    const previewFrame = document.getElementById('preview-frame');
    if (previewFrame && previewFrame.src !== data.url) {
      previewFrame.src = data.url;
    }
  }

  onConnected() {
    // Add visual indicator
    this.showConnectionStatus('connected');
    
    // Request current state
    this.subscription.perform('request_state');
  }

  onDisconnected() {
    // Show reconnection UI
    this.showConnectionStatus('disconnected');
    
    // Attempt reconnection
    setTimeout(() => this.connect(), 3000);
  }

  showConnectionStatus(status) {
    let indicator = document.getElementById('hmr-status');
    
    if (!indicator) {
      indicator = document.createElement('div');
      indicator.id = 'hmr-status';
      indicator.style.cssText = `
        position: fixed;
        bottom: 10px;
        left: 10px;
        padding: 4px 8px;
        border-radius: 3px;
        font-size: 12px;
        font-family: monospace;
        z-index: 999997;
        transition: all 0.3s;
      `;
      document.body.appendChild(indicator);
    }
    
    if (status === 'connected') {
      indicator.style.background = '#4caf50';
      indicator.style.color = 'white';
      indicator.textContent = 'HMR Connected';
      setTimeout(() => indicator.style.opacity = '0.3', 2000);
    } else {
      indicator.style.background = '#ff9800';
      indicator.style.color = 'white';
      indicator.style.opacity = '1';
      indicator.textContent = 'HMR Reconnecting...';
    }
  }

  escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }

  // Public API for manual updates
  updateFile(path, content) {
    this.subscription.perform('update_file', { path, content });
  }

  reloadComponent(componentName) {
    this.subscription.perform('reload_component', { component: componentName });
  }

  refreshPreview() {
    this.subscription.perform('refresh_preview');
  }

  disconnect() {
    if (this.subscription) {
      this.subscription.unsubscribe();
      this.subscription = null;
    }
  }
}

// Auto-initialize for preview frames
document.addEventListener('DOMContentLoaded', () => {
  const appId = document.querySelector('[data-app-id]')?.dataset.appId;
  
  if (appId && window.location.pathname.includes('/preview')) {
    window.hmrClient = new HMRClient(appId);
    window.hmrClient.connect();
    
    console.log('[HMR] Client initialized for app', appId);
  }
});

// Export for manual usage
export default HMRClient;