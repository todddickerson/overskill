# AI App Building Standards

**THIS FILE IS AUTOMATICALLY INCLUDED IN EVERY AI GENERATION REQUEST**
**DO NOT EDIT WITHOUT UPDATING CLAUDE.md**

## Core Principles

You are building professional-grade web applications that rival Lovable.dev, Cursor, Claude Code, and Base44 in quality. Every app you generate should demonstrate:
- Professional design with sophisticated color palettes and theming systems
- Complete functionality with proper state management, not prototypes
- Industry-appropriate aesthetics with modern UI patterns
- Smooth user experiences with loading states, error handling, and animations
- Modern, clean code architecture with feature-based organization
- Accessibility-first approach with semantic HTML and ARIA attributes
- Mobile-first responsive design that works on all devices
- Integration-ready architecture for Supabase, authentication, and APIs

## Required Technology Stack

### Base Technologies (React Only)
ALL applications must be React single-page applications (SPAs) using CDN-based React, not bundled.

### Approved External Resources
- ✅ **Tailwind CSS**: Via CDN (https://cdn.tailwindcss.com) with custom configuration
- ✅ **Google Fonts**: Inter for UI, editorial fonts for content
- ✅ **Lucide Icons**: Modern icon set via CDN (https://unpkg.com/lucide@latest)
- ✅ **Font Awesome**: Icons via CDN as fallback
- ✅ **Animate.css**: Animations via CDN
- ✅ **Alpine.js**: For enhanced interactivity (via CDN)
- ✅ **Chart.js/Recharts**: For data visualization (via CDN)
- ✅ **Shadcn/ui**: Copy components directly - use Radix UI patterns
- ✅ **date-fns**: For date formatting (via CDN)
- ✅ **DOMPurify**: For sanitizing user content (via CDN)

#### React-Specific Resources (CDN Only)
- ✅ **React + ReactDOM**: Via CDN with Babel transformer for JSX
- ✅ **@heroicons/react**: Icons optimized for React (via CDN)
- ✅ **React Router**: For client-side routing (via CDN)
- ✅ **Supabase JS**: Database client (via CDN)

### File Structure Requirements (React Apps Only)

**ALL apps are React applications. NO vanilla HTML/JS apps.**

```
index.html       - HTML entry point with React CDN scripts (REQUIRED)
src/App.jsx      - Main React component (JSX, NOT TSX)
src/main.jsx     - ReactDOM render entry point (JSX, NOT TSX)  
src/index.css    - Global styles and Tailwind imports
src/lib/supabase.js - Supabase client configuration
src/lib/analytics.js - Analytics tracking utilities
src/components/  - Reusable React components (JSX only)
```

**CRITICAL: ALL files must use .jsx extension, NEVER .tsx TypeScript files**

## Database & Authentication Rules

### MANDATORY: Apps with User Data MUST Include Authentication

When generating ANY app with user-specific data (todos, notes, posts, etc.):

1. **ALWAYS create Auth component** at `src/components/Auth.jsx`:
```jsx
import { useState } from 'react'
import { supabase } from '../lib/supabase'

export function Auth({ onAuth }) {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [isSignUp, setIsSignUp] = useState(false)
  const [loading, setLoading] = useState(false)

  const handleSubmit = async (e) => {
    e.preventDefault()
    setLoading(true)
    
    const { data, error } = isSignUp
      ? await supabase.auth.signUp({ email, password })
      : await supabase.auth.signInWithPassword({ email, password })
    
    if (error) alert(error.message)
    else if (data.user) onAuth(data.user)
    
    setLoading(false)
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50">
      <div className="max-w-md w-full space-y-8 p-8 bg-white rounded-lg shadow">
        <h2 className="text-center text-3xl font-extrabold text-gray-900">
          {isSignUp ? 'Create Account' : 'Sign In'}
        </h2>
        <form onSubmit={handleSubmit} className="mt-8 space-y-6">
          <div className="space-y-4">
            <input 
              type="email" 
              value={email} 
              onChange={(e) => setEmail(e.target.value)} 
              className="w-full px-3 py-2 border border-gray-300 rounded-md text-gray-900 placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-indigo-500"
              placeholder="Email address"
              required 
            />
            <input 
              type="password" 
              value={password} 
              onChange={(e) => setPassword(e.target.value)} 
              className="w-full px-3 py-2 border border-gray-300 rounded-md text-gray-900 placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-indigo-500"
              placeholder="Password"
              required 
            />
          </div>
          <button 
            type="submit"
            disabled={loading}
            className="w-full py-2 px-4 bg-indigo-600 text-white rounded-md hover:bg-indigo-700 disabled:opacity-50"
          >
            {loading ? 'Loading...' : (isSignUp ? 'Sign Up' : 'Sign In')}
          </button>
          <button 
            type="button" 
            onClick={() => setIsSignUp(!isSignUp)}
            className="w-full text-center text-indigo-600 hover:text-indigo-500"
          >
            {isSignUp ? 'Have account? Sign In' : 'Need account? Sign Up'}
          </button>
        </form>
      </div>
    </div>
  )
}
```

2. **ALWAYS check authentication in App.jsx**:
```jsx
const [user, setUser] = useState(null)

useEffect(() => {
  supabase.auth.getSession().then(({ data: { session } }) => {
    setUser(session?.user ?? null)
  })
}, [])

if (!user) return <Auth onAuth={setUser} />
```

3. **ALWAYS use full table names with app ID**:
```jsx
// ✅ CORRECT - uses app ID from environment
const tableName = `app_${window.ENV.APP_ID}_todos`
await supabase.from(tableName).select('*')

// ❌ WRONG - missing app ID prefix
await supabase.from('todos').select('*')
```

4. **ALWAYS include user_id in queries**:
```jsx
// ✅ CORRECT - filtered by user
await supabase
  .from(`app_${window.ENV.APP_ID}_todos`)
  .select('*')
  .eq('user_id', user.id)

// ✅ CORRECT - include user_id when creating
await supabase
  .from(`app_${window.ENV.APP_ID}_todos`)
  .insert([{ text, user_id: user.id }])
```

### React App Template (CDN-based)

#### index.html Template
```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>App Name</title>
  <script src="https://cdn.tailwindcss.com"></script>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
</head>
<body class="font-['Inter'] antialiased">
  <div id="root"></div>
  
  <!-- React via CDN -->
  <script crossorigin src="https://unpkg.com/react@18/umd/react.development.js"></script>
  <script crossorigin src="https://unpkg.com/react-dom@18/umd/react-dom.development.js"></script>
  <script src="https://unpkg.com/@babel/standalone/babel.min.js"></script>
  
  <!-- Supabase client -->
  <script src="https://unpkg.com/@supabase/supabase-js@2"></script>
  
  <!-- Load app -->
  <script type="text/babel" src="src/main.jsx"></script>
</body>
</html>
```

#### src/main.jsx Template
```javascript
const { createRoot } = ReactDOM;
const { StrictMode } = React;

createRoot(document.getElementById('root')).render(
  React.createElement(StrictMode, null,
    React.createElement(App, null)
  )
);
```

#### Component Pattern (NO TypeScript syntax)
```javascript
// Use React.createElement or JSX with Babel transform
function MyComponent({ title, children }) {
  const [state, setState] = React.useState(false);
  
  return React.createElement('div', {
    className: 'p-4 bg-white rounded-lg'
  }, 
    React.createElement('h2', { className: 'text-xl font-bold' }, title),
    children
  );
}

// Or with JSX (requires Babel transform in browser)
function MyComponent({ title, children }) {
  const [state, setState] = React.useState(false);
  
  return (
    <div className="p-4 bg-white rounded-lg">
      <h2 className="text-xl font-bold">{title}</h2>
      {children}
    </div>
  );
}
```

### Multi-Page App Structure
When creating multi-page applications, use this structure:
```
index.html       - Home/landing page (REQUIRED)
dashboard.html   - Dashboard page (for apps with user areas)
about.html       - About page
contact.html     - Contact page
login.html       - Login page (if auth required)
register.html    - Registration page (if auth required)
profile.html     - User profile page
settings.html    - Settings page
404.html         - Error page

app.js           - Shared JavaScript (loaded on all pages)
styles.css       - Shared styles (loaded on all pages)
page-specific.js - Optional page-specific JavaScript
```

### Multi-Page Navigation Pattern
```html
<!-- Consistent navigation across all pages -->
<nav class="bg-white dark:bg-gray-800 border-b border-gray-200 dark:border-gray-700">
  <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
    <div class="flex justify-between h-16">
      <div class="flex items-center space-x-8">
        <a href="index.html" class="text-lg font-semibold">AppName</a>
        <div class="hidden md:flex space-x-4">
          <a href="index.html" class="px-3 py-2 rounded-md text-sm font-medium hover:bg-gray-100 dark:hover:bg-gray-700">Home</a>
          <a href="dashboard.html" class="px-3 py-2 rounded-md text-sm font-medium hover:bg-gray-100 dark:hover:bg-gray-700">Dashboard</a>
          <a href="about.html" class="px-3 py-2 rounded-md text-sm font-medium hover:bg-gray-100 dark:hover:bg-gray-700">About</a>
          <a href="contact.html" class="px-3 py-2 rounded-md text-sm font-medium hover:bg-gray-100 dark:hover:bg-gray-700">Contact</a>
        </div>
      </div>
      <div class="flex items-center space-x-4">
        <a href="login.html" class="text-sm">Sign in</a>
        <a href="register.html" class="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 text-sm">Sign up</a>
      </div>
    </div>
  </div>
</nav>
```

### Page-Specific JavaScript Loading
```javascript
// app.js - Shared across all pages
const app = {
  currentPage: window.location.pathname.split('/').pop() || 'index.html',
  
  init() {
    console.log('Initializing app on page:', this.currentPage);
    this.setupCommonFeatures();
    this.loadPageSpecificLogic();
  },
  
  setupCommonFeatures() {
    // Navigation, auth check, theme toggle, etc.
    this.highlightActiveNavLink();
    this.setupMobileMenu();
    this.checkAuthentication();
  },
  
  loadPageSpecificLogic() {
    // Load page-specific functionality
    switch(this.currentPage) {
      case 'dashboard.html':
        this.initDashboard();
        break;
      case 'profile.html':
        this.initProfile();
        break;
      case 'settings.html':
        this.initSettings();
        break;
      default:
        // Common page logic
        break;
    }
  },
  
  highlightActiveNavLink() {
    // Add active class to current page link
    document.querySelectorAll('nav a').forEach(link => {
      if (link.getAttribute('href') === this.currentPage) {
        link.classList.add('bg-gray-100', 'dark:bg-gray-700');
      }
    });
  }
};

// Initialize on DOM ready
document.addEventListener('DOMContentLoaded', () => app.init());
```

### Consistent Page Structure Template
```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Page Title - AppName</title>
  <script src="https://cdn.tailwindcss.com"></script>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
  <link rel="stylesheet" href="styles.css">
</head>
<body class="font-['Inter'] antialiased bg-gray-50 dark:bg-gray-900">
  <!-- Navigation (consistent across pages) -->
  <nav><!-- ... --></nav>
  
  <!-- Page Content -->
  <main class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
    <!-- Page-specific content here -->
  </main>
  
  <!-- Footer (consistent across pages) -->
  <footer class="bg-white dark:bg-gray-800 border-t border-gray-200 dark:border-gray-700 mt-auto">
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
      <p class="text-center text-sm text-gray-500 dark:text-gray-400">
        © 2024 AppName. All rights reserved.
      </p>
    </div>
  </footer>
  
  <script src="app.js"></script>
</body>
</html>
```

## Design Standards

### Professional Color Palettes with CSS Variables
Always use HSL-based color systems for easy theming:
```css
:root {
  /* Base44/shadcn inspired HSL color system */
  --background: 0 0% 100%;          /* White background */
  --foreground: 222.2 84% 4.9%;     /* Near black text */
  
  --card: 0 0% 100%;                /* Card backgrounds */
  --card-foreground: 222.2 84% 4.9%;
  
  --primary: 222.2 47.4% 11.2%;     /* Primary brand color */
  --primary-foreground: 210 40% 98%;
  
  --secondary: 210 40% 96.1%;       /* Secondary actions */
  --secondary-foreground: 222.2 47.4% 11.2%;
  
  --muted: 210 40% 96.1%;           /* Muted backgrounds */
  --muted-foreground: 215.4 16.3% 46.9%;
  
  --accent: 210 40% 96.1%;          /* Accent color */
  --accent-foreground: 222.2 47.4% 11.2%;
  
  --destructive: 0 84.2% 60.2%;     /* Error/delete actions */
  --destructive-foreground: 210 40% 98%;
  
  --border: 214.3 31.8% 91.4%;      /* Borders */
  --input: 214.3 31.8% 91.4%;       /* Input borders */
  --ring: 222.2 84% 4.9%;           /* Focus rings */
  
  --radius: 0.5rem;                  /* Border radius */
}

/* Dark mode support */
.dark {
  --background: 222.2 84% 4.9%;
  --foreground: 210 40% 98%;
  /* ... additional dark mode variables */
}
```

### Typography Hierarchy
```css
/* Consistent type scale */
.text-xs: 0.75rem;      /* 12px */
.text-sm: 0.875rem;     /* 14px */
.text-base: 1rem;       /* 16px */
.text-lg: 1.125rem;     /* 18px */
.text-xl: 1.25rem;      /* 20px */
.text-2xl: 1.5rem;      /* 24px */
.text-3xl: 1.875rem;    /* 30px */
.text-4xl: 2.25rem;     /* 36px */
```

### Component Patterns

#### Professional Buttons
```html
<!-- Primary Button -->
<button class="px-4 py-2 bg-slate-900 text-white rounded-lg hover:bg-slate-800 transition-colors duration-200 font-medium">
  Action
</button>

<!-- Secondary Button -->
<button class="px-4 py-2 bg-white text-slate-900 border border-slate-300 rounded-lg hover:bg-slate-50 transition-colors duration-200 font-medium">
  Secondary
</button>
```

#### Professional Cards (Base44 Style)
```html
<!-- Basic Card -->
<div class="bg-white rounded-xl shadow-sm border border-slate-200 p-6 hover:shadow-md transition-all duration-200">
  <h3 class="text-lg font-semibold text-slate-900 mb-2">Card Title</h3>
  <p class="text-slate-600">Card content with proper typography.</p>
</div>

<!-- Interactive Card with Hover State -->
<div class="group bg-white rounded-xl shadow-sm border border-slate-200 p-6 hover:shadow-lg hover:border-slate-300 transition-all duration-200 cursor-pointer">
  <div class="flex items-start justify-between mb-4">
    <div class="p-2 bg-slate-100 rounded-lg group-hover:bg-slate-200 transition-colors">
      <svg class="w-6 h-6 text-slate-700" fill="none" stroke="currentColor"><!-- Icon --></svg>
    </div>
    <span class="text-xs text-slate-500 font-medium">2 min ago</span>
  </div>
  <h3 class="text-lg font-semibold text-slate-900 mb-2 group-hover:text-blue-600 transition-colors">Interactive Card</h3>
  <p class="text-slate-600 line-clamp-2">Content that reveals more on interaction...</p>
</div>
  <h3 class="text-lg font-semibold text-slate-900">Card Title</h3>
  <p class="text-slate-600 mt-2">Card content goes here</p>
</div>
```

#### Form Inputs

**CRITICAL: Always include text-slate-900 for input text color to prevent white-on-white text issues**

```html
<div class="space-y-2">
  <label class="text-sm font-medium text-slate-700">Label</label>
  <input type="text" class="w-full px-3 py-2 border border-slate-300 rounded-lg text-slate-900 placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent">
</div>
```

**Required input classes:**
- `text-slate-900` or `text-gray-900` - ALWAYS include for text color
- `placeholder-slate-500` - For placeholder text visibility
- `bg-white` - Explicit background if needed
- `focus:outline-none focus:ring-2` - For accessibility

## JavaScript Standards

### Modern ES6+ Features (REQUIRED)
```javascript
// Always use modern JavaScript
const app = {
  // Use async/await for asynchronous operations
  async init() {
    try {
      const data = await this.fetchData();
      this.render(data);
    } catch (error) {
      this.handleError(error);
    }
  },

  // Use arrow functions for callbacks
  setupEventListeners() {
    document.querySelectorAll('.btn').forEach(btn => {
      btn.addEventListener('click', (e) => this.handleClick(e));
    });
  },

  // Use template literals for HTML generation
  generateCard({ title, description }) {
    return `
      <div class="card">
        <h3>${this.escapeHtml(title)}</h3>
        <p>${this.escapeHtml(description)}</p>
      </div>
    `;
  },

  // Always escape user input
  escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }
};

// Initialize on DOM ready
document.addEventListener('DOMContentLoaded', () => app.init());
```

### Data Management
```javascript
// Use localStorage for persistence
const storage = {
  save(key, data) {
    localStorage.setItem(key, JSON.stringify(data));
  },
  
  load(key) {
    const data = localStorage.getItem(key);
    return data ? JSON.parse(data) : null;
  },
  
  remove(key) {
    localStorage.removeItem(key);
  }
};

// State management pattern
const state = {
  data: [],
  
  add(item) {
    this.data.push(item);
    this.persist();
    this.notify();
  },
  
  persist() {
    storage.save('appData', this.data);
  },
  
  notify() {
    document.dispatchEvent(new CustomEvent('stateChanged', { 
      detail: this.data 
    }));
  }
};
```

## User Experience Requirements

### Loading States
Always show loading feedback:
```html
<div class="flex items-center justify-center p-8">
  <div class="animate-spin rounded-full h-8 w-8 border-b-2 border-slate-900"></div>
</div>
```

### DOM Safety and Element Selection

**CRITICAL**: Always ensure JavaScript and HTML structures match to prevent runtime errors:

```javascript
// ❌ BAD: Assumes specific DOM structure that may not exist
const root = document.getElementById('root');
root.innerHTML = generateHTML(); // Will throw error if root is null

// ✅ GOOD: Defensive programming with null checks
const container = document.getElementById('app-container') || document.body;
if (container) {
  container.innerHTML = generateHTML();
} else {
  console.warn('Container element not found');
}

// ✅ BETTER: Use existing HTML structure instead of replacing
function initializeApp() {
  // Work with existing DOM elements instead of replacing entire sections
  const existingButtons = document.querySelectorAll('[data-action]');
  existingButtons.forEach(button => {
    button.addEventListener('click', handleAction);
  });
}

// ✅ BEST: Provide fallbacks and graceful degradation
function setupEventListeners() {
  // Multiple fallback selectors
  const addButton = document.querySelector('#add-btn') || 
                   document.querySelector('.add-button') || 
                   document.querySelector('[data-add]');
                   
  if (addButton) {
    addButton.addEventListener('click', handleAdd);
  }
}
```

**HTML-JavaScript Coordination Rules:**
1. If JavaScript expects specific IDs/classes, ensure HTML contains them
2. Always use null checks before manipulating DOM elements  
3. Prefer enhancing existing HTML over replacing it entirely
4. Use data attributes for JavaScript hooks: `data-action`, `data-toggle`, etc.
5. Test that all `getElementById`, `querySelector` calls have matching HTML elements

### Error Handling
Professional error messages:
```html
<div class="bg-red-50 border border-red-200 text-red-800 px-4 py-3 rounded-lg">
  <p class="font-medium">Error</p>
  <p class="text-sm mt-1">Something went wrong. Please try again.</p>
</div>
```

### Success Feedback
Clear success indicators:
```html
<div class="bg-green-50 border border-green-200 text-green-800 px-4 py-3 rounded-lg">
  <p class="font-medium">Success!</p>
  <p class="text-sm mt-1">Your changes have been saved.</p>
</div>
```

### Transitions and Animations
Smooth, professional interactions:
```css
/* Use Tailwind's transition utilities */
.transition-all
.duration-200
.ease-in-out
.hover:scale-105
.hover:shadow-lg
```

## Data and Content

### Sample Data Requirements
ALWAYS include realistic sample data:
```javascript
// Bad: Empty or minimal data
const items = [];

// Good: Rich, realistic sample data
const items = [
  {
    id: 1,
    title: "Q4 Financial Report",
    description: "Comprehensive analysis of Q4 2024 performance metrics",
    status: "completed",
    priority: "high",
    dueDate: "2024-12-31",
    assignee: "Sarah Johnson",
    tags: ["finance", "quarterly", "urgent"],
    progress: 100
  },
  // Include 5-10 realistic samples
];
```

### Placeholder Content
Use professional placeholder text, not Lorem Ipsum:
```javascript
// Bad
"Lorem ipsum dolor sit amet..."

// Good
"Track your team's progress with real-time analytics and insights."
"Streamline your workflow with our intuitive project management tools."
```

## Mobile Responsiveness

### Required Breakpoint Classes
```html
<!-- Mobile-first responsive design -->
<div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
  <!-- Content -->
</div>

<!-- Responsive padding -->
<div class="px-4 md:px-6 lg:px-8">
  <!-- Content -->
</div>

<!-- Responsive text -->
<h1 class="text-2xl md:text-3xl lg:text-4xl font-bold">
  Title
</h1>
```

## Accessibility Standards

### Required Attributes
```html
<!-- Semantic HTML -->
<nav role="navigation" aria-label="Main navigation">
  <!-- Navigation items -->
</nav>

<!-- Form accessibility -->
<label for="email" class="sr-only">Email</label>
<input id="email" type="email" aria-required="true" aria-invalid="false">

<!-- Button accessibility -->
<button aria-label="Close dialog" aria-pressed="false">
  <svg><!-- Icon --></svg>
</button>

<!-- Keyboard navigation -->
<div tabindex="0" role="button" onkeydown="if(event.key === 'Enter') handleClick()">
  Interactive element
</div>
```

## Performance Optimization

### Image Optimization
```html
<!-- Use appropriate image formats and lazy loading -->
<img src="image.jpg" 
     alt="Descriptive alt text" 
     loading="lazy"
     class="w-full h-auto">
```

### JavaScript Optimization
```javascript
// Debounce expensive operations
function debounce(func, wait) {
  let timeout;
  return function executedFunction(...args) {
    const later = () => {
      clearTimeout(timeout);
      func(...args);
    };
    clearTimeout(timeout);
    timeout = setTimeout(later, wait);
  };
}

// Use event delegation
document.addEventListener('click', (e) => {
  if (e.target.matches('.btn')) {
    handleButtonClick(e.target);
  }
});
```

## Database Integration

When the app requires data persistence:

### Supabase Integration Pattern
```javascript
// App will receive Supabase credentials via window.SUPABASE_CONFIG
const db = {
  async init() {
    if (window.SUPABASE_CONFIG) {
      // Use provided Supabase instance
      this.client = window.supabaseClient;
    } else {
      // Fall back to localStorage
      this.useLocalStorage = true;
    }
  },
  
  async save(table, data) {
    if (this.useLocalStorage) {
      const existing = JSON.parse(localStorage.getItem(table) || '[]');
      existing.push({ ...data, id: Date.now() });
      localStorage.setItem(table, JSON.stringify(existing));
      return data;
    }
    // Supabase save logic
    const { data: result, error } = await this.client
      .from(table)
      .insert(data);
    return result;
  }
};
```

## Security Requirements

### Input Validation
```javascript
// Always validate and sanitize user input
function validateEmail(email) {
  const re = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  return re.test(email);
}

function sanitizeInput(input) {
  return input.trim().replace(/<script>/gi, '');
}
```

### XSS Prevention
```javascript
// Always escape HTML in user content
function escapeHtml(unsafe) {
  return unsafe
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}
```

## Platform Integration (Supabase & APIs)

### Environment Variables & Configuration
```javascript
// Apps receive configuration via window globals
const config = {
  // Supabase configuration (provided by platform)
  supabase: window.SUPABASE_CONFIG || null,
  supabaseUrl: window.SUPABASE_URL,
  supabaseKey: window.SUPABASE_ANON_KEY,
  
  // API endpoints (provided by platform)
  apiUrl: window.API_URL || '/api',
  
  // App metadata
  appId: window.APP_ID,
  userId: window.USER_ID,
  
  // Feature flags
  features: window.FEATURES || {}
};

// Initialize Supabase client if available
let supabase = null;
if (config.supabaseUrl && config.supabaseKey) {
  // Supabase will be loaded via CDN
  supabase = window.supabase.createClient(config.supabaseUrl, config.supabaseKey);
}
```

### Supabase Integration Patterns
```javascript
// Database operations with fallback to localStorage
const dataService = {
  async init() {
    this.isOnline = !!supabase;
    if (!this.isOnline) {
      console.log('Running in offline mode with localStorage');
    }
  },
  
  async create(table, data) {
    if (this.isOnline) {
      const { data: result, error } = await supabase
        .from(table)
        .insert(data)
        .select()
        .single();
      if (error) throw error;
      return result;
    } else {
      // Fallback to localStorage
      const items = JSON.parse(localStorage.getItem(table) || '[]');
      const newItem = { ...data, id: Date.now(), created_at: new Date().toISOString() };
      items.push(newItem);
      localStorage.setItem(table, JSON.stringify(items));
      return newItem;
    }
  },
  
  async read(table, filters = {}) {
    if (this.isOnline) {
      let query = supabase.from(table).select('*');
      Object.entries(filters).forEach(([key, value]) => {
        query = query.eq(key, value);
      });
      const { data, error } = await query;
      if (error) throw error;
      return data;
    } else {
      const items = JSON.parse(localStorage.getItem(table) || '[]');
      return items.filter(item => 
        Object.entries(filters).every(([key, value]) => item[key] === value)
      );
    }
  },
  
  async update(table, id, data) {
    if (this.isOnline) {
      const { data: result, error } = await supabase
        .from(table)
        .update(data)
        .eq('id', id)
        .select()
        .single();
      if (error) throw error;
      return result;
    } else {
      const items = JSON.parse(localStorage.getItem(table) || '[]');
      const index = items.findIndex(item => item.id === id);
      if (index !== -1) {
        items[index] = { ...items[index], ...data, updated_at: new Date().toISOString() };
        localStorage.setItem(table, JSON.stringify(items));
        return items[index];
      }
      throw new Error('Item not found');
    }
  },
  
  async delete(table, id) {
    if (this.isOnline) {
      const { error } = await supabase
        .from(table)
        .delete()
        .eq('id', id);
      if (error) throw error;
      return true;
    } else {
      const items = JSON.parse(localStorage.getItem(table) || '[]');
      const filtered = items.filter(item => item.id !== id);
      localStorage.setItem(table, JSON.stringify(filtered));
      return true;
    }
  }
};
```

### Authentication Pattern (Supabase Auth)
```javascript
const auth = {
  async signIn(email, password) {
    if (!supabase) {
      // Mock auth for development
      localStorage.setItem('user', JSON.stringify({ email, id: Date.now() }));
      return { user: { email } };
    }
    
    const { data, error } = await supabase.auth.signInWithPassword({
      email,
      password
    });
    
    if (error) throw error;
    return data;
  },
  
  async signOut() {
    if (!supabase) {
      localStorage.removeItem('user');
      return;
    }
    
    const { error } = await supabase.auth.signOut();
    if (error) throw error;
  },
  
  async getUser() {
    if (!supabase) {
      return JSON.parse(localStorage.getItem('user') || 'null');
    }
    
    const { data: { user } } = await supabase.auth.getUser();
    return user;
  },
  
  onAuthStateChange(callback) {
    if (!supabase) {
      // Mock auth state for development
      callback('SIGNED_IN', JSON.parse(localStorage.getItem('user') || 'null'));
      return () => {};
    }
    
    const { data: { subscription } } = supabase.auth.onAuthStateChange(callback);
    return () => subscription.unsubscribe();
  }
};
```

## Common App Patterns

### Dashboard Layout
```html
<div class="min-h-screen bg-slate-50">
  <!-- Header -->
  <header class="bg-white border-b border-slate-200">
    <div class="px-6 py-4">
      <h1 class="text-xl font-semibold">Dashboard</h1>
    </div>
  </header>
  
  <!-- Main Content -->
  <main class="p-6">
    <!-- Stats Grid -->
    <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mb-6">
      <!-- Stat Cards -->
    </div>
    
    <!-- Content Area -->
    <div class="bg-white rounded-xl shadow-sm p-6">
      <!-- Main content -->
    </div>
  </main>
</div>
```

### Form Pattern
```html
<form class="space-y-6 max-w-md mx-auto">
  <div>
    <label class="block text-sm font-medium text-slate-700 mb-2">
      Field Label
    </label>
    <input type="text" 
           class="w-full px-3 py-2 border border-slate-300 rounded-lg text-slate-900 placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-blue-500">
  </div>
  
  <button type="submit" 
          class="w-full bg-blue-600 text-white py-2 px-4 rounded-lg hover:bg-blue-700 transition-colors">
    Submit
  </button>
</form>
```

## Testing Your Implementation

Before considering any file complete, verify:
1. ✅ All interactive elements work properly
2. ✅ Forms validate and submit correctly
3. ✅ Error states are handled gracefully
4. ✅ Loading states appear during async operations
5. ✅ Mobile responsive design works
6. ✅ Keyboard navigation functions
7. ✅ Sample data displays correctly
8. ✅ Colors and typography are consistent
9. ✅ Transitions are smooth
10. ✅ Code follows modern JavaScript patterns

## Advanced UI Components (Base44 Inspired)

### Empty States
```html
<div class="flex flex-col items-center justify-center py-12 px-4">
  <div class="w-20 h-20 bg-slate-100 rounded-full flex items-center justify-center mb-4">
    <svg class="w-10 h-10 text-slate-400" fill="none" stroke="currentColor">
      <!-- Relevant icon -->
    </svg>
  </div>
  <h3 class="text-lg font-semibold text-slate-900 mb-2">No items yet</h3>
  <p class="text-slate-600 text-center max-w-sm mb-6">
    Get started by creating your first item. It only takes a few seconds.
  </p>
  <button class="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors">
    Create First Item
  </button>
</div>
```

### Skeleton Loaders
```html
<div class="animate-pulse">
  <div class="h-4 bg-slate-200 rounded w-3/4 mb-4"></div>
  <div class="h-4 bg-slate-200 rounded w-1/2 mb-4"></div>
  <div class="h-4 bg-slate-200 rounded w-5/6"></div>
</div>
```

### Toast Notifications
```javascript
const toast = {
  show(message, type = 'info') {
    const colors = {
      success: 'bg-green-500',
      error: 'bg-red-500',
      warning: 'bg-yellow-500',
      info: 'bg-blue-500'
    };
    
    const toast = document.createElement('div');
    toast.className = `fixed bottom-4 right-4 ${colors[type]} text-white px-6 py-3 rounded-lg shadow-lg transform translate-y-0 transition-all duration-300 z-50`;
    toast.textContent = message;
    
    document.body.appendChild(toast);
    
    setTimeout(() => {
      toast.classList.add('translate-y-full', 'opacity-0');
      setTimeout(() => toast.remove(), 300);
    }, 3000);
  }
};
```

### Modal/Dialog Pattern
```html
<div id="modal" class="fixed inset-0 z-50 hidden">
  <!-- Backdrop -->
  <div class="fixed inset-0 bg-black/50 transition-opacity" onclick="closeModal()"></div>
  
  <!-- Modal -->
  <div class="fixed left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2 w-full max-w-md">
    <div class="bg-white rounded-xl shadow-xl p-6">
      <h2 class="text-xl font-semibold text-slate-900 mb-4">Modal Title</h2>
      <p class="text-slate-600 mb-6">Modal content goes here...</p>
      <div class="flex gap-3 justify-end">
        <button onclick="closeModal()" class="px-4 py-2 text-slate-600 hover:text-slate-900">
          Cancel
        </button>
        <button class="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700">
          Confirm
        </button>
      </div>
    </div>
  </div>
</div>
```

### Data Table Pattern
```html
<div class="overflow-x-auto">
  <table class="w-full">
    <thead>
      <tr class="border-b border-slate-200">
        <th class="text-left py-3 px-4 font-medium text-slate-900">Name</th>
        <th class="text-left py-3 px-4 font-medium text-slate-900">Status</th>
        <th class="text-left py-3 px-4 font-medium text-slate-900">Date</th>
        <th class="text-right py-3 px-4 font-medium text-slate-900">Actions</th>
      </tr>
    </thead>
    <tbody>
      <tr class="border-b border-slate-100 hover:bg-slate-50 transition-colors">
        <td class="py-3 px-4">
          <div class="font-medium text-slate-900">Item Name</div>
          <div class="text-sm text-slate-500">Additional info</div>
        </td>
        <td class="py-3 px-4">
          <span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
            Active
          </span>
        </td>
        <td class="py-3 px-4 text-slate-600">Dec 4, 2024</td>
        <td class="py-3 px-4 text-right">
          <button class="text-slate-600 hover:text-slate-900">
            <svg class="w-5 h-5" fill="none" stroke="currentColor"><!-- Menu icon --></svg>
          </button>
        </td>
      </tr>
    </tbody>
  </table>
</div>
```

## State Management Pattern
```javascript
// Simple state management with pub/sub pattern
class AppState {
  constructor() {
    this.state = {};
    this.listeners = {};
  }
  
  set(key, value) {
    const oldValue = this.state[key];
    this.state[key] = value;
    
    if (oldValue !== value) {
      this.emit(key, value, oldValue);
    }
  }
  
  get(key) {
    return this.state[key];
  }
  
  on(key, callback) {
    if (!this.listeners[key]) {
      this.listeners[key] = [];
    }
    this.listeners[key].push(callback);
    
    // Return unsubscribe function
    return () => {
      this.listeners[key] = this.listeners[key].filter(cb => cb !== callback);
    };
  }
  
  emit(key, value, oldValue) {
    if (this.listeners[key]) {
      this.listeners[key].forEach(callback => {
        callback(value, oldValue);
      });
    }
  }
}

const appState = new AppState();

// Usage
appState.on('user', (user) => {
  console.log('User changed:', user);
  updateUIForUser(user);
});

appState.set('user', { name: 'John', email: 'john@example.com' });
```

## DO NOT:
- ❌ Use Lorem Ipsum text - use realistic, contextual content
- ❌ Leave empty functions or TODO comments
- ❌ Create minimal/prototype implementations
- ❌ Use inline styles when Tailwind classes exist
- ❌ Forget loading, error, and empty states
- ❌ Skip input validation and sanitization
- ❌ Use outdated JavaScript patterns (var, callbacks instead of async/await)
- ❌ Create apps without realistic sample data (minimum 5-10 items)
- ❌ Ignore mobile responsiveness and touch interactions
- ❌ Skip accessibility attributes and keyboard navigation
- ❌ Use generic variable names like 'data' or 'item'
- ❌ Hardcode values that should be configurable
- ❌ Mix concerns (UI logic with business logic)

## ALWAYS:
- ✅ Include Tailwind CSS via CDN with custom CSS variables
- ✅ Use HSL-based professional color palettes for theming
- ✅ Add loading, error, and empty states for all data operations
- ✅ Include 5-10 realistic, contextual sample data items
- ✅ Implement complete CRUD operations with optimistic updates
- ✅ Add smooth transitions and micro-interactions
- ✅ Use semantic HTML with proper heading hierarchy
- ✅ Validate and sanitize all user inputs
- ✅ Make it mobile-first responsive with touch support
- ✅ Follow WCAG accessibility standards
- ✅ Implement proper error boundaries and fallbacks
- ✅ Use feature-based code organization
- ✅ Add keyboard shortcuts for power users
- ✅ Include proper meta tags for SEO
- ✅ Implement offline-first with localStorage fallback
- ✅ Use consistent naming conventions throughout
- ✅ Add helpful comments for complex logic only
- ✅ Test on multiple screen sizes before considering complete