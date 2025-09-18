// Analytics tracking removed for simplified deployment
// This is a stub file to maintain compatibility with existing imports

class NoOpAnalytics {
  track(event: string, data: Record<string, any> = {}) {
    // No-op: Analytics disabled
    console.log('[Analytics Disabled]', event, data);
  }

  trackClick(element: string, properties?: Record<string, any>) {
    // No-op: Analytics disabled
  }

  trackFormSubmit(formName: string, properties?: Record<string, any>) {
    // No-op: Analytics disabled
  }

  trackError(error: Error, context?: Record<string, any>) {
    // Still log errors to console for debugging
    console.error('Error:', error.message, context);
  }

  trackTiming(metric: string, duration: number, properties?: Record<string, any>) {
    // No-op: Analytics disabled
  }
}

export const analytics = new NoOpAnalytics();
