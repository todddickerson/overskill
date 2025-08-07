const path = require('path');
const { execSync } = require("child_process");
const glob  = require('glob').sync

// Default to 'light' theme if THEME env var is not set (for IDE support)
const theme = process.env.THEME || 'light'
  
let themeConfig
try {
  const themeConfigFile = execSync(`bundle exec bin/theme tailwind-config ${theme}`).toString().trim()
  themeConfig = require(themeConfigFile)
} catch (error) {
  // Fallback config for when running outside Rails context (e.g., IDE extensions)
  console.warn('Using fallback Tailwind config. Set THEME env variable for full config.')
  themeConfig = require('./tmp/gems/bullet_train-themes-light/tailwind.light.config.js')
}

// *** Uncomment these if required for your overrides ***

// const defaultTheme = require('tailwindcss/defaultTheme')
// const colors = require('tailwindcss/colors')

// *** Add your own overrides here ***

// Override primary colors with Overskill brand colors
themeConfig.theme.extend.colors.primary = {
  50: '#fefce8',
  100: '#fef9c3',
  200: '#fef08a',
  300: '#fde047',
  400: '#facc15',
  500: '#E3F300', // Main brand color from logo
  600: '#ca8a04',
  700: '#a16207',
  800: '#854d0e',
  900: '#713f12',
}

// Override secondary colors
themeConfig.theme.extend.colors.secondary = {
  50: '#f7f8e8',
  100: '#ecedbc',
  200: '#dde08a',
  300: '#c9cd4f',
  400: '#b3b424',
  500: '#9a9618',
  600: '#7c7613',
  700: '#6A7107', // Dark olive from logo
  800: '#504613',
  900: '#433a15',
}

module.exports = themeConfig