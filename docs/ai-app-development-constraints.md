# AI App Development Constraints for OverSkill Platform

## CRITICAL: Platform Architecture Understanding

OverSkill is a **platform that generates apps**, not a traditional development environment. Apps created within OverSkill have specific constraints and capabilities that must be understood and enforced.

## App Deployment Model

### What OverSkill Apps ARE:
- **File-based applications** consisting of HTML, CSS, and JavaScript files
- **Client-side only** applications with no backend/server components
- **Deployed to Cloudflare Workers** as preview environments
- **Sandboxed** applications running in iframe contexts
- **Direct execution** - files are served as-is without build processes

### What OverSkill Apps are NOT:
- ❌ **Node.js applications** with package.json, npm install, build processes
- ❌ **Full-stack applications** with backends, databases, or server-side code
- ❌ **Standalone repositories** that can be cloned, built, or deployed independently
- ❌ **Applications with access** to file systems, process management, or system APIs

## File Structure and Constraints

### Allowed File Types:
- ✅ `index.html` - Main entry point (required)
- ✅ `app.js` - Main JavaScript logic
- ✅ `styles.css` - Styling (can include Tailwind classes)
- ✅ `components.js` - Component definitions
- ✅ Additional `.js`, `.css`, `.html` files as needed

### Approved External Resources (via CDN):
- ✅ **React**: Component-based architecture via `https://unpkg.com/react@18/umd/react.production.min.js`
- ✅ **React DOM**: React rendering via `https://unpkg.com/react-dom@18/umd/react-dom.production.min.js`
- ✅ **Babel Standalone**: JSX compilation via `https://unpkg.com/@babel/standalone/babel.min.js`
- ✅ **Tailwind CSS**: Full minified build via `https://cdn.tailwindcss.com`
- ✅ **Shadcn/ui Components**: Professional React components adapted from `https://ui.shadcn.com/`
- ✅ **Alpine.js**: Lightweight JavaScript framework for vanilla apps via `https://unpkg.com/alpinejs`
- ✅ **Chart.js**: Professional data visualization via `https://cdn.jsdelivr.net/npm/chart.js`
- ✅ **Lucide Icons**: Consistent SVG icon system via `https://unpkg.com/lucide`
- ✅ **Animate.css**: Professional animations via `https://cdnjs.cloudflare.com/ajax/libs/animate.css`
- ✅ **Web Fonts**: Google Fonts and other font CDNs

### Forbidden Operations:
- ❌ **Package management**: No npm, yarn, package.json, node_modules
- ❌ **Build tools**: No webpack, vite, rollup, build scripts
- ❌ **Server operations**: No npm start, dev servers, backend processes
- ❌ **System access**: No file system operations, process spawning, shell commands
- ❌ **External dependencies**: No installing packages or importing from CDNs arbitrarily

## Development Constraints

### JavaScript Limitations:
```javascript
// ✅ ALLOWED - Direct JavaScript
function createApp() {
  const app = document.createElement('div');
  app.innerHTML = '<h1>Hello World</h1>';
  document.body.appendChild(app);
}

// ✅ ALLOWED - Modern ES6+ features
const users = data.map(user => ({ ...user, active: true }));

// ✅ ALLOWED - DOM manipulation
document.addEventListener('DOMContentLoaded', initializeApp);

// ❌ FORBIDDEN - Import statements for packages
import React from 'react';
import axios from 'axios';

// ❌ FORBIDDEN - Node.js APIs
const fs = require('fs');
const path = require('path');

// ❌ FORBIDDEN - Build-time features
export { MyComponent };
```

### HTML Structure:
```html
<!-- ✅ ALLOWED - Standard HTML -->
<!DOCTYPE html>
<html>
<head>
  <title>My App</title>
  <link rel="stylesheet" href="styles.css">
</head>
<body>
  <div id="app"></div>
  <script src="app.js"></script>
</body>
</html>

<!-- ❌ FORBIDDEN - Build-time features -->
<script type="module" src="./components/MyComponent.js"></script>
<link rel="stylesheet" href="./node_modules/bootstrap/dist/css/bootstrap.css">
```

### CSS Constraints:
```css
/* ✅ ALLOWED - Standard CSS */
.container { display: flex; }
.button { background: #007bff; }

/* ✅ ALLOWED - Modern CSS features */
.grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); }

/* ✅ ALLOWED - Tailwind utility classes (via CDN) */
.bg-blue-500 { /* Applied via Tailwind CDN */ }
.flex.items-center.justify-between { /* Multiple utilities */ }

/* ❌ FORBIDDEN - CSS preprocessors that require compilation */
$primary-color: #007bff; /* SCSS */
@primary-color: #007bff; /* LESS */
```

### HTML Structure with Tailwind:
```html
<!-- ✅ ALLOWED - Tailwind CSS via CDN -->
<!DOCTYPE html>
<html>
<head>
  <title>My App</title>
  <link href="https://cdn.tailwindcss.com" rel="stylesheet">
  <link rel="stylesheet" href="styles.css">
</head>
<body class="bg-gray-100 font-sans">
  <div id="app" class="container mx-auto px-4 py-8"></div>
  <script src="app.js"></script>
</body>
</html>

<!-- ❌ FORBIDDEN - Build-time features -->
<script type="module" src="./components/MyComponent.js"></script>
<link rel="stylesheet" href="./node_modules/bootstrap/dist/css/bootstrap.css">
```

### Professional UI with Shadcn/ui Components:
```html
<!-- ✅ ALLOWED - Professional App with Full Approved Stack -->
<!DOCTYPE html>
<html>
<head>
  <title>Professional Dashboard</title>
  <!-- Tailwind CSS for styling -->
  <link href="https://cdn.tailwindcss.com" rel="stylesheet">
  <!-- Animate.css for smooth animations -->
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/animate.css/4.1.1/animate.min.css">
  <!-- Google Fonts for typography -->
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&display=swap" rel="stylesheet">
</head>
<body class="font-inter bg-slate-50">
  <div class="container mx-auto p-6" x-data="dashboardApp()">
    
    <!-- Header with Alpine.js interactivity -->
    <header class="flex items-center justify-between mb-8 animate__animated animate__fadeInDown">
      <h1 class="text-3xl font-semibold text-slate-900">Dashboard</h1>
      <button 
        x-on:click="toggleDarkMode()" 
        class="inline-flex items-center justify-center rounded-md text-sm font-medium bg-slate-900 text-white hover:bg-slate-800 h-10 px-4 py-2 transition-colors">
        <i data-lucide="sun" class="w-4 h-4 mr-2"></i>
        Toggle Theme
      </button>
    </header>

    <!-- Stats Cards with Shadcn/ui styling -->
    <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
      <div class="rounded-lg border bg-white shadow-sm p-6 animate__animated animate__fadeInUp" 
           style="animation-delay: 0.1s">
        <div class="flex items-center">
          <i data-lucide="users" class="w-8 h-8 text-blue-500"></i>
          <div class="ml-4">
            <p class="text-sm font-medium text-slate-600">Total Users</p>
            <p class="text-2xl font-bold text-slate-900" x-text="stats.users">1,234</p>
          </div>
        </div>
      </div>
      
      <div class="rounded-lg border bg-white shadow-sm p-6 animate__animated animate__fadeInUp" 
           style="animation-delay: 0.2s">
        <div class="flex items-center">
          <i data-lucide="dollar-sign" class="w-8 h-8 text-green-500"></i>
          <div class="ml-4">
            <p class="text-sm font-medium text-slate-600">Revenue</p>
            <p class="text-2xl font-bold text-slate-900" x-text="'$' + stats.revenue">$12,345</p>
          </div>
        </div>
      </div>
      
      <div class="rounded-lg border bg-white shadow-sm p-6 animate__animated animate__fadeInUp" 
           style="animation-delay: 0.3s">
        <div class="flex items-center">
          <i data-lucide="trending-up" class="w-8 h-8 text-purple-500"></i>
          <div class="ml-4">
            <p class="text-sm font-medium text-slate-600">Growth</p>
            <p class="text-2xl font-bold text-slate-900" x-text="stats.growth + '%'">23%</p>
          </div>
        </div>
      </div>
    </div>

    <!-- Chart.js Chart -->
    <div class="rounded-lg border bg-white shadow-sm p-6 animate__animated animate__fadeInUp" 
         style="animation-delay: 0.4s">
      <h2 class="text-xl font-semibold mb-4">Sales Overview</h2>
      <canvas id="salesChart" width="400" height="200"></canvas>
    </div>

  </div>

  <!-- Alpine.js for interactivity -->
  <script src="https://unpkg.com/alpinejs@3.x.x/dist/cdn.min.js" defer></script>
  <!-- Chart.js for data visualization -->
  <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
  <!-- Lucide icons -->
  <script src="https://unpkg.com/lucide@latest/dist/umd/lucide.js"></script>
  
  <script>
    // Alpine.js app data
    function dashboardApp() {
      return {
        stats: {
          users: 1234,
          revenue: 12345,
          growth: 23
        },
        toggleDarkMode() {
          document.body.classList.toggle('dark');
        }
      }
    }

    // Initialize Chart.js chart
    document.addEventListener('DOMContentLoaded', function() {
      const ctx = document.getElementById('salesChart').getContext('2d');
      new Chart(ctx, {
        type: 'line',
        data: {
          labels: ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun'],
          datasets: [{
            label: 'Sales',
            data: [12, 19, 3, 5, 2, 3],
            borderColor: 'rgb(59, 130, 246)',
            backgroundColor: 'rgba(59, 130, 246, 0.1)',
            tension: 0.4
          }]
        },
        options: {
          responsive: true,
          plugins: {
            legend: {
              display: false
            }
          }
        }
      });

      // Initialize Lucide icons
      lucide.createIcons();
    });
  </script>
</body>
</html>
```

## Debugging and Error Handling Approach

### ✅ CORRECT Debugging Strategy:
1. **Console logging**: Use `console.log()`, `console.error()` for debugging
2. **DOM inspection**: Check if elements exist before manipulating
3. **Error boundaries**: Wrap code in try-catch blocks
4. **Browser DevTools**: Utilize browser's built-in debugging tools
5. **Validation**: Check data types and values before operations

### ❌ INCORRECT Debugging Strategy:
1. ~~Running build processes to check for compilation errors~~
2. ~~Setting up development servers~~
3. ~~Installing debugging packages or tools~~
4. ~~Creating health check endpoints~~
5. ~~Setting up remote error logging services~~

## Common App Issues and Solutions

### Issue: "App isn't working"
```javascript
// ✅ CORRECT approach - Direct debugging
function debugApp() {
  console.log('App initialization started');
  
  // Check if DOM is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initializeApp);
  } else {
    initializeApp();
  }
}

function initializeApp() {
  try {
    // Check if required elements exist
    const appContainer = document.getElementById('app');
    if (!appContainer) {
      console.error('App container not found');
      return;
    }
    
    // Initialize your app logic here
    setupEventListeners();
    loadInitialData();
    
    console.log('App initialized successfully');
  } catch (error) {
    console.error('App initialization failed:', error);
    showErrorMessage('App failed to load. Please refresh the page.');
  }
}

function showErrorMessage(message) {
  const errorDiv = document.createElement('div');
  errorDiv.style.cssText = 'color: red; padding: 20px; font-family: Arial;';
  errorDiv.textContent = message;
  document.body.appendChild(errorDiv);
}
```

### Issue: JavaScript Errors
```javascript
// ✅ CORRECT - Defensive programming
function safeDataAccess(data) {
  if (!data || typeof data !== 'object') {
    console.warn('Invalid data provided:', data);
    return [];
  }
  
  return data.items || [];
}

// ✅ CORRECT - Event handling with error catching
function setupEventListeners() {
  const button = document.getElementById('myButton');
  if (button) {
    button.addEventListener('click', function(event) {
      try {
        handleButtonClick(event);
      } catch (error) {
        console.error('Button click handler failed:', error);
      }
    });
  }
}
```

## Tools and Available Resources

### ✅ Available for App Development:
- **Modern JavaScript** (ES6+, async/await, fetch API)
- **CSS3** (flexbox, grid, animations, custom properties)
- **HTML5** (semantic elements, local storage, canvas)
- **Browser APIs** (DOM, localStorage, sessionStorage, URL, FormData)
- **Basic AJAX** (fetch for external APIs where allowed)

### ❌ NOT Available:
- **Package managers** (npm, yarn, pnpm)
- **Build tools** (webpack, rollup, parcel, vite)
- **Preprocessors** (TypeScript, Sass, Less, PostCSS)
- **Testing frameworks** (Jest, Mocha, Cypress)
- **Development servers** (webpack-dev-server, vite dev)
- **Node.js APIs** (fs, path, http, process)

## AI Assistant Guidelines

When helping with OverSkill app development:

### DO:
1. ✅ Focus on **direct file editing** and **client-side solutions**
2. ✅ Use **vanilla JavaScript, HTML, and CSS**
3. ✅ Implement **error handling with try-catch and console logging**
4. ✅ Suggest **DOM-based debugging techniques**
5. ✅ Create **self-contained, file-based solutions**
6. ✅ Consider **browser compatibility and modern web standards**

### DON'T:
1. ❌ Suggest **npm commands or package management**
2. ❌ Recommend **build processes or compilation steps**
3. ❌ Propose **server-side solutions or backend changes**
4. ❌ Suggest **external tool installation**
5. ❌ Recommend **framework-specific solutions** that require build processes
6. ❌ Propose **system-level debugging or server management**

## Example: Correct Response to "App isn't working"

```javascript
// CORRECT approach - Debug and fix within file constraints
function diagnoseAndFixApp() {
  console.log('=== App Diagnosis Started ===');
  
  // 1. Check DOM readiness
  if (document.readyState !== 'complete') {
    console.log('DOM not ready, waiting...');
    window.addEventListener('load', diagnoseAndFixApp);
    return;
  }
  
  // 2. Check for critical elements
  const criticalElements = ['app', 'main-container', 'content'];
  const missingElements = criticalElements.filter(id => !document.getElementById(id));
  
  if (missingElements.length > 0) {
    console.error('Missing critical elements:', missingElements);
    createFallbackUI();
    return;
  }
  
  // 3. Check for JavaScript errors
  window.addEventListener('error', function(event) {
    console.error('JavaScript error detected:', event.error);
    showUserFriendlyError('Something went wrong. Please refresh the page.');
  });
  
  // 4. Initialize app safely
  try {
    initializeMainApp();
    console.log('✅ App working correctly');
  } catch (error) {
    console.error('App initialization failed:', error);
    createFallbackUI();
  }
}

function createFallbackUI() {
  document.body.innerHTML = `
    <div style="padding: 20px; font-family: Arial, sans-serif;">
      <h1>App Loading...</h1>
      <p>If this message persists, please refresh the page.</p>
      <button onclick="location.reload()">Refresh Page</button>
    </div>
  `;
}

// Run diagnosis when page loads
diagnoseAndFixApp();
```

## Summary

OverSkill apps are **client-side, file-based applications** deployed to Cloudflare Workers. All development must work within these constraints, focusing on direct file editing, vanilla web technologies, and client-side debugging techniques. No build processes, package management, or server-side operations are available or appropriate.