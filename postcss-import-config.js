const { execSync } = require("child_process");

const theme = process.env.THEME || 'light'
const themeStylesheetsDir = execSync(`bundle exec bin/theme stylesheets-dir ${theme} 2> /dev/null`).toString().trim()
const themeStylesheet = execSync(`bundle exec bin/theme tailwind-stylesheet ${theme} 2> /dev/null`).toString().trim()

module.exports = {
  resolve: (id, basedir, importOptions) => {
    if (id.startsWith('$ThemeStylesheetsDir')) {
      id = id.replace('$ThemeStylesheetsDir', themeStylesheetsDir);
    } else if (id.startsWith('$ThemeStylesheet')) {
      id = id.replace('$ThemeStylesheet', themeStylesheet);
    }
    return id;
  }
}
