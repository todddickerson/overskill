/**
 * Route Configuration for {{APP_NAME}}
 * 
 * This file defines all the routes available in the application
 * Add new routes here as the app grows
 */

export interface RouteConfig {
  path: string;
  name: string;
  protected: boolean;
  showInNavigation?: boolean;
  icon?: string;
}

/**
 * Core application routes
 */
export const routes: RouteConfig[] = [
  {
    path: '/dashboard',
    name: 'Dashboard',
    protected: true,
    showInNavigation: true,
    icon: 'dashboard'
  },
  {
    path: '/auth/login',
    name: 'Login',
    protected: false,
    showInNavigation: false
  },
  {
    path: '/auth/signup',
    name: 'Sign Up',
    protected: false,
    showInNavigation: false
  },
  {
    path: '/auth/forgot-password',
    name: 'Forgot Password',
    protected: false,
    showInNavigation: false
  }
];

/**
 * Get routes for navigation (protected routes only)
 */
export const getNavigationRoutes = (): RouteConfig[] => {
  return routes.filter(route => route.showInNavigation && route.protected);
};

/**
 * Get route by path
 */
export const getRouteByPath = (path: string): RouteConfig | undefined => {
  return routes.find(route => route.path === path);
};

/**
 * Check if a route is protected
 */
export const isProtectedRoute = (path: string): boolean => {
  const route = getRouteByPath(path);
  return route?.protected ?? true; // Default to protected
};