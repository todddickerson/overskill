#!/usr/bin/env node

/**
 * Pre-build validation and auto-fix script
 * Prevents common build failures from AI-generated code
 */

import fs from 'fs';
import path from 'path';
import { glob } from 'glob';

// ANSI color codes for console output
const colors = {
  reset: '\x1b[0m',
  red: '\x1b[31m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m'
};

let hasErrors = false;
let fixedCount = 0;

// 1. Fix invalid Tailwind classes in CSS files
async function fixTailwindClasses() {
  console.log(`${colors.blue}🔍 Checking CSS files for invalid Tailwind classes...${colors.reset}`);
  
  const cssFiles = await glob('src/**/*.css');
  
  // Map of invalid classes to valid replacements
  const classReplacements = {
    'shadow-3xl': 'shadow-2xl',
    'shadow-4xl': 'shadow-2xl',
    'shadow-5xl': 'shadow-2xl',
    'text-9xl': 'text-8xl',
    'text-10xl': 'text-8xl',
    'rounded-5xl': 'rounded-3xl',
    'rounded-6xl': 'rounded-3xl',
    'p-20': 'p-16',
    'p-24': 'p-16',
    'm-20': 'm-16',
    'm-24': 'm-16'
  };
  
  for (const file of cssFiles) {
    let content = fs.readFileSync(file, 'utf-8');
    let modified = false;
    
    for (const [invalid, valid] of Object.entries(classReplacements)) {
      const regex = new RegExp(`\\b${invalid}\\b`, 'g');
      if (regex.test(content)) {
        console.log(`${colors.yellow}  ⚠️  Found invalid class '${invalid}' in ${file}${colors.reset}`);
        content = content.replace(regex, valid);
        modified = true;
        fixedCount++;
      }
    }
    
    if (modified) {
      fs.writeFileSync(file, content);
      console.log(`${colors.green}  ✅ Fixed invalid classes in ${file}${colors.reset}`);
    }
  }
}

// 2. Validate JSX/TSX syntax
async function validateJSXSyntax() {
  console.log(`${colors.blue}🔍 Validating JSX/TSX syntax...${colors.reset}`);
  
  const jsxFiles = await glob('src/**/*.{jsx,tsx}');
  
  for (const file of jsxFiles) {
    const content = fs.readFileSync(file, 'utf-8');
    
    // Check for mismatched tags using a simple stack
    const tagStack = [];
    const tagRegex = /<\/?([A-Z][A-Za-z]*)[^>]*>/g;
    let match;
    
    while ((match = tagRegex.exec(content)) !== null) {
      const fullTag = match[0];
      const tagName = match[1];
      
      if (fullTag.startsWith('</')) {
        // Closing tag
        if (tagStack.length === 0 || tagStack[tagStack.length - 1] !== tagName) {
          console.log(`${colors.red}  ❌ Mismatched closing tag </${tagName}> in ${file}${colors.reset}`);
          hasErrors = true;
        } else {
          tagStack.pop();
        }
      } else if (!fullTag.endsWith('/>')) {
        // Opening tag (not self-closing)
        tagStack.push(tagName);
      }
    }
    
    if (tagStack.length > 0) {
      console.log(`${colors.red}  ❌ Unclosed tags in ${file}: ${tagStack.join(', ')}${colors.reset}`);
      hasErrors = true;
    }
  }
}

// 3. Validate TypeScript imports
async function validateImports() {
  console.log(`${colors.blue}🔍 Checking for missing imports...${colors.reset}`);
  
  const tsxFiles = await glob('src/**/*.{ts,tsx}');
  
  for (const file of tsxFiles) {
    const content = fs.readFileSync(file, 'utf-8');
    
    // Common components that need imports
    const componentPatterns = [
      { pattern: /<(Card|CardContent|CardHeader|CardFooter|CardTitle|CardDescription)\b/, import: "import { $1 } from '@/components/ui/card'" },
      { pattern: /<(Button)\b/, import: "import { Button } from '@/components/ui/button'" },
      { pattern: /<(Input)\b/, import: "import { Input } from '@/components/ui/input'" },
      { pattern: /<(Label)\b/, import: "import { Label } from '@/components/ui/label'" },
      { pattern: /<(Select|SelectContent|SelectItem|SelectTrigger|SelectValue)\b/, import: "import { $1 } from '@/components/ui/select'" }
    ];
    
    let importsToAdd = [];
    
    for (const { pattern, import: importStatement } of componentPatterns) {
      if (pattern.test(content) && !content.includes(importStatement.split(' from ')[0])) {
        importsToAdd.push(importStatement);
      }
    }
    
    if (importsToAdd.length > 0) {
      console.log(`${colors.yellow}  ⚠️  Missing imports in ${file}${colors.reset}`);
      
      // Add imports at the beginning of the file
      const updatedContent = importsToAdd.join('\n') + '\n\n' + content;
      fs.writeFileSync(file, updatedContent);
      
      console.log(`${colors.green}  ✅ Added ${importsToAdd.length} missing imports${colors.reset}`);
      fixedCount++;
    }
  }
}

// 4. Fix common TypeScript errors
async function fixTypeScriptErrors() {
  console.log(`${colors.blue}🔍 Fixing common TypeScript errors...${colors.reset}`);
  
  const tsxFiles = await glob('src/**/*.{ts,tsx}');
  
  for (const file of tsxFiles) {
    let content = fs.readFileSync(file, 'utf-8');
    let modified = false;
    
    // Fix missing return statements in components
    if (content.includes('export default function') || content.includes('export function')) {
      // Ensure components have return statements
      const functionRegex = /export\s+(default\s+)?function\s+\w+\([^)]*\)\s*{([^}]*)}/g;
      content = content.replace(functionRegex, (match, defaultExport, body) => {
        if (!body.includes('return')) {
          console.log(`${colors.yellow}  ⚠️  Missing return statement in ${file}${colors.reset}`);
          // This is too complex to auto-fix reliably
          hasErrors = true;
        }
        return match;
      });
    }
    
    // Fix incorrect useState syntax
    const incorrectUseState = /const\s+(\w+)\s*=\s*useState\(/g;
    if (incorrectUseState.test(content)) {
      content = content.replace(incorrectUseState, 'const [$1, set$1] = useState(');
      modified = true;
      fixedCount++;
    }
    
    if (modified) {
      fs.writeFileSync(file, content);
      console.log(`${colors.green}  ✅ Fixed TypeScript issues in ${file}${colors.reset}`);
    }
  }
}

// Main execution
async function main() {
  console.log(`${colors.blue}🚀 Starting pre-build validation...${colors.reset}\n`);
  
  try {
    await fixTailwindClasses();
    await validateJSXSyntax();
    await validateImports();
    await fixTypeScriptErrors();
    
    console.log(`\n${colors.blue}📊 Validation Summary:${colors.reset}`);
    console.log(`  ${colors.green}✅ Fixed ${fixedCount} issues automatically${colors.reset}`);
    
    if (hasErrors) {
      console.log(`  ${colors.red}❌ Found errors that require manual fixing${colors.reset}`);
      console.log(`\n${colors.red}⚠️  Build may fail due to unresolved issues${colors.reset}`);
      process.exit(1);
    } else {
      console.log(`  ${colors.green}✅ All checks passed!${colors.reset}`);
    }
  } catch (error) {
    console.error(`${colors.red}❌ Validation script failed: ${error.message}${colors.reset}`);
    process.exit(1);
  }
}

main();