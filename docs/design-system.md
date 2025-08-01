# OverSkill Design System

## Design Principles

### 1. Clean & Modern
- Generous whitespace and clean layouts
- Subtle shadows and borders
- Consistent rounded corners (rounded-lg as default)
- Minimal, purposeful design elements

### 2. Smooth Animations
- Fade-in animations for all modals and overlays
- Smooth transitions for hover states (duration-200)
- Gentle scale animations for interactive elements
- Loading states with subtle pulse animations

### 3. Consistent Typography
- Clear hierarchy with proper font weights
- Consistent text colors using semantic naming
- Readable line heights and letter spacing

## Component Standards

### Colors & Theming
```css
/* Light Mode (Default) */
--bg-primary: white
--bg-secondary: gray-50
--bg-tertiary: gray-100
--text-primary: gray-900
--text-secondary: gray-600
--text-tertiary: gray-500
--border-primary: gray-200
--border-secondary: gray-100

/* Dark Mode */
--bg-primary: gray-900
--bg-secondary: gray-800
--bg-tertiary: gray-700
--text-primary: gray-100
--text-secondary: gray-300
--text-tertiary: gray-400
--border-primary: gray-700
--border-secondary: gray-600
```

### Spacing & Layout
- Container padding: `px-6 py-4` for cards, `px-4 py-3` for compact elements
- Section spacing: `space-y-6` for major sections, `space-y-4` for related items
- Button padding: `px-4 py-2` for normal, `px-6 py-3` for primary actions

### Buttons
```html
<!-- Primary Button -->
<button class="bg-blue-600 hover:bg-blue-700 text-white font-medium px-6 py-3 rounded-lg transition-all duration-200 transform hover:scale-105 shadow-sm hover:shadow-md">
  Primary Action
</button>

<!-- Secondary Button -->
<button class="bg-white dark:bg-gray-800 text-gray-700 dark:text-gray-300 border border-gray-200 dark:border-gray-600 font-medium px-4 py-2 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-700 transition-all duration-200">
  Secondary
</button>

<!-- Danger Button -->
<button class="bg-red-600 hover:bg-red-700 text-white font-medium px-4 py-2 rounded-lg transition-all duration-200">
  Delete
</button>
```

### Cards & Containers
```html
<!-- Standard Card -->
<div class="bg-white dark:bg-gray-800 rounded-lg shadow-sm border border-gray-200 dark:border-gray-700 transition-all duration-200 hover:shadow-md">
  <div class="px-6 py-4">
    <!-- Content -->
  </div>
</div>

<!-- Interactive Card -->
<div class="bg-white dark:bg-gray-800 rounded-lg shadow-sm border border-gray-200 dark:border-gray-700 transition-all duration-200 hover:shadow-lg hover:scale-[1.02] cursor-pointer">
  <!-- Content -->
</div>
```

### Modals & Overlays
```html
<!-- Modal Backdrop -->
<div class="fixed inset-0 bg-black bg-opacity-50 backdrop-blur-sm z-50 flex items-center justify-center animate-fadeIn">
  <!-- Modal Content -->
  <div class="bg-white dark:bg-gray-800 rounded-xl shadow-2xl max-w-2xl w-full mx-4 animate-slideUp">
    <!-- Modal body -->
  </div>
</div>
```

### Form Elements
```html
<!-- Text Input -->
<input class="w-full px-4 py-3 border border-gray-200 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 placeholder-gray-500 dark:placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all duration-200">

<!-- Textarea -->
<textarea class="w-full px-4 py-3 border border-gray-200 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 placeholder-gray-500 dark:placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all duration-200 resize-none">
```

### Navigation & Headers
```html
<!-- Header -->
<div class="bg-white dark:bg-gray-800 border-b border-gray-200 dark:border-gray-700 px-6 py-4 transition-colors duration-200">
  <!-- Header content -->
</div>

<!-- Navigation Item -->
<a class="flex items-center px-4 py-2 text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-700 hover:text-gray-900 dark:hover:text-white rounded-lg transition-all duration-200">
  <!-- Nav content -->
</a>
```

### Loading States
```html
<!-- Skeleton Loading -->
<div class="animate-pulse">
  <div class="h-4 bg-gray-200 dark:bg-gray-700 rounded w-3/4 mb-2"></div>
  <div class="h-4 bg-gray-200 dark:bg-gray-700 rounded w-1/2"></div>
</div>

<!-- Spinner -->
<div class="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600"></div>
```

## Animation Classes
Add these to your CSS:

```css
@keyframes fadeIn {
  from { opacity: 0; }
  to { opacity: 1; }
}

@keyframes slideUp {
  from { 
    opacity: 0; 
    transform: translateY(16px); 
  }
  to { 
    opacity: 1; 
    transform: translateY(0); 
  }
}

@keyframes slideDown {
  from { 
    opacity: 0; 
    transform: translateY(-16px); 
  }
  to { 
    opacity: 1; 
    transform: translateY(0); 
  }
}

.animate-fadeIn {
  animation: fadeIn 0.2s ease-out;
}

.animate-slideUp {
  animation: slideUp 0.3s ease-out;
}

.animate-slideDown {
  animation: slideDown 0.3s ease-out;
}
```

## Interactive States

### Hover States
- Subtle scale transformations: `hover:scale-105` for buttons, `hover:scale-[1.02]` for cards
- Color transitions with 200ms duration
- Shadow elevation changes: `hover:shadow-md` to `hover:shadow-lg`

### Focus States
- Ring-based focus: `focus:ring-2 focus:ring-blue-500`
- Border color changes: `focus:border-blue-500`
- Always remove default outline: `focus:outline-none`

### Active States
- Slight scale down: `active:scale-95`
- Deeper shadow: `active:shadow-inner`

## Responsive Design
- Mobile-first approach
- Consistent breakpoints: `sm:`, `md:`, `lg:`, `xl:`
- Adaptive spacing and typography scaling

## Accessibility
- Proper ARIA labels and roles
- Keyboard navigation support
- High contrast ratios in both light and dark modes
- Focus indicators for all interactive elements

## Usage Guidelines
1. Always use transition classes for smooth interactions
2. Maintain consistent spacing using the defined scales
3. Apply hover states to all interactive elements
4. Use semantic color naming (primary, secondary, danger)
5. Ensure dark mode compatibility for all components
6. Test animations on slower devices - keep them subtle and fast