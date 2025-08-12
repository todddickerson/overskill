class OverskillAnalytics {
  private appId: string;
  private sessionId: string;
  
  constructor() {
    this.appId = import.meta.env.VITE_APP_ID || 'unknown';
    this.sessionId = this.generateSessionId();
    
    // Track initial page view
    this.track('page_view', {
      url: window.location.href,
      referrer: document.referrer,
      title: document.title
    });
    
    // Track page visibility changes
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'hidden') {
        this.track('page_hide');
      } else {
        this.track('page_show');
      }
    });
  }
  
  private generateSessionId(): string {
    return `${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
  }
  
  track(event: string, data: Record<string, any> = {}) {
    // Skip analytics in development unless explicitly enabled
    if (import.meta.env.DEV && !import.meta.env.VITE_ANALYTICS_ENABLED) {
      console.log('[Analytics Dev]', event, data);
      return;
    }
    
    fetch('https://overskill.app/api/v1/analytics/track', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        app_id: this.appId,
        session_id: this.sessionId,
        event,
        data,
        timestamp: Date.now(),
        user_agent: navigator.userAgent,
        screen_resolution: `${window.screen.width}x${window.screen.height}`,
        viewport: `${window.innerWidth}x${window.innerHeight}`,
        platform: navigator.platform
      })
    }).catch(() => {}); // Silent fail
  }
  
  // Convenience methods for common events
  trackClick(element: string, properties?: Record<string, any>) {
    this.track('click', { element, ...properties });
  }
  
  trackFormSubmit(formName: string, properties?: Record<string, any>) {
    this.track('form_submit', { form_name: formName, ...properties });
  }
  
  trackError(error: Error, context?: Record<string, any>) {
    this.track('error', {
      message: error.message,
      stack: error.stack,
      ...context
    });
  }
  
  trackTiming(metric: string, duration: number, properties?: Record<string, any>) {
    this.track('timing', { metric, duration, ...properties });
  }
}

// Auto-initialize
export const analytics = new OverskillAnalytics();
