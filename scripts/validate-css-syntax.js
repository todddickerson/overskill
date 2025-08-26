#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const postcss = require('postcss');

/**
 * CSS Syntax Validator for Build Pipeline
 * Catches CSS syntax errors before Vite build fails
 */

const colors = {
  reset: '\x1b[0m',
  bright: '\x1b[1m',
  red: '\x1b[31m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
};

function validateCSSFile(filePath) {
  try {
    const content = fs.readFileSync(filePath, 'utf8');
    
    // Quick brace matching check
    const openBraces = (content.match(/{/g) || []).length;
    const closeBraces = (content.match(/}/g) || []).length;
    
    if (openBraces !== closeBraces) {
      console.error(`${colors.red}❌ Brace mismatch in ${filePath}: ${openBraces} open, ${closeBraces} close${colors.reset}`);
      
      // Try to find the approximate location
      const lines = content.split('\n');
      let braceCount = 0;
      let errorLine = -1;
      
      for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        braceCount += (line.match(/{/g) || []).length;
        braceCount -= (line.match(/}/g) || []).length;
        
        if (braceCount < 0) {
          errorLine = i + 1;
          console.error(`${colors.red}  Extra closing brace detected around line ${errorLine}: ${line.trim()}${colors.reset}`);
          break;
        }
      }
      
      return false;
    }
    
    // Use PostCSS to parse and validate
    return new Promise((resolve) => {
      postcss()
        .process(content, { from: filePath })
        .then(() => {
          console.log(`${colors.green}✅ CSS syntax valid: ${filePath}${colors.reset}`);
          resolve(true);
        })
        .catch((error) => {
          console.error(`${colors.red}❌ CSS parsing error in ${filePath}:${colors.reset}`);
          console.error(`${colors.red}  Line ${error.line}: ${error.reason}${colors.reset}`);
          
          // Show context around error
          const lines = content.split('\n');
          const errorLine = error.line - 1;
          const start = Math.max(0, errorLine - 2);
          const end = Math.min(lines.length, errorLine + 3);
          
          console.log(`${colors.yellow}  Context:${colors.reset}`);
          for (let i = start; i < end; i++) {
            const prefix = i === errorLine ? '>>> ' : '    ';
            console.log(`${colors.yellow}  ${i + 1}: ${prefix}${lines[i]}${colors.reset}`);
          }
          
          resolve(false);
        });
    });
    
  } catch (error) {
    console.error(`${colors.red}❌ Failed to read ${filePath}: ${error.message}${colors.reset}`);
    return false;
  }
}

async function validateAllCSS() {
  console.log(`${colors.blue}🔍 Validating CSS files...${colors.reset}`);
  
  const cssFiles = [
    'src/index.css',
    'src/App.css',
  ].filter(file => fs.existsSync(file));
  
  if (cssFiles.length === 0) {
    console.log(`${colors.yellow}⚠️  No CSS files found to validate${colors.reset}`);
    return true;
  }
  
  const results = await Promise.all(cssFiles.map(validateCSSFile));
  const allValid = results.every(r => r === true);
  
  if (allValid) {
    console.log(`${colors.green}✅ All CSS files are syntactically valid${colors.reset}`);
  } else {
    console.log(`${colors.red}❌ CSS validation failed - fix errors above${colors.reset}`);
    process.exit(1);
  }
  
  return allValid;
}

// Run validation if called directly
if (require.main === module) {
  validateAllCSS();
}

module.exports = { validateCSSFile, validateAllCSS };