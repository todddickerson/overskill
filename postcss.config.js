const { execSync } = require("child_process");

const theme = process.env.THEME || 'light'
const postcssImportConfigFile = execSync(`bundle exec bin/theme postcss-import-config ${theme}`).toString().trim()
const postcssImportConfig = require(postcssImportConfigFile)

module.exports = {
  plugins: [
    require('postcss-import')(postcssImportConfig),
    require('postcss-extend-rule'),
    require('tailwindcss/nesting'),
    require('tailwindcss'),
    require('autoprefixer'),
  ]
}
