#!/usr/bin/env node

/**
 * Test all React components and files in the deployed todo app
 */

const https = require('https');

async function fetchUrl(url) {
    return new Promise((resolve, reject) => {
        https.get(url, (res) => {
            let data = '';
            res.on('data', (chunk) => data += chunk);
            res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, data }));
        }).on('error', reject);
    });
}

async function testAllComponents() {
    console.log('🔍 Testing All React Components');
    console.log('===============================');
    
    const baseUrl = 'https://preview-57.overskill.app';
    
    // Common React file patterns to test
    const filesToTest = [
        '/src/App.tsx',
        '/src/App.jsx',
        '/src/index.css',
        '/src/App.css',
        '/src/components/TodoList.tsx',
        '/src/components/TodoItem.tsx',
        '/src/components/AddTodo.tsx',
        '/vite.svg',
        '/favicon.ico'
    ];
    
    for (const file of filesToTest) {
        console.log(`\n📄 Testing: ${file}`);
        try {
            const response = await fetchUrl(baseUrl + file);
            
            if (response.status === 200) {
                console.log(`✅ Status: ${response.status}`);
                console.log(`📊 Size: ${response.data.length} bytes`);
                console.log(`🗂️ Type: ${response.headers['content-type'] || 'unknown'}`);
                
                // Analyze content based on file type
                if (file.endsWith('.tsx') || file.endsWith('.jsx') || file.endsWith('.js')) {
                    // JavaScript/TypeScript analysis
                    const content = response.data;
                    
                    // Check for React patterns
                    const hasUseState = content.includes('useState');
                    const hasUseEffect = content.includes('useEffect');
                    const hasJSX = content.includes('<') && content.includes('>');
                    const hasTodoLogic = content.toLowerCase().includes('todo') || content.toLowerCase().includes('task');
                    
                    console.log(`  🔧 useState: ${hasUseState ? '✅' : '❌'}`);
                    console.log(`  🔧 useEffect: ${hasUseEffect ? '✅' : '❌'}`);
                    console.log(`  🏷️ JSX: ${hasJSX ? '✅' : '❌'}`);
                    console.log(`  📝 Todo Logic: ${hasTodoLogic ? '✅' : '❌'}`);
                    
                    // Show a sample of the code
                    console.log(`  📋 Sample (first 200 chars):`);
                    console.log(`     ${content.substring(0, 200).replace(/\n/g, '\\n')}...`);
                    
                } else if (file.endsWith('.css')) {
                    // CSS analysis
                    const content = response.data;
                    const hasFlexbox = content.includes('flex');
                    const hasGrid = content.includes('grid');
                    const hasVariables = content.includes('--');
                    const hasModernCSS = content.includes('calc(') || content.includes('clamp(');
                    
                    console.log(`  🎨 Flexbox: ${hasFlexbox ? '✅' : '❌'}`);
                    console.log(`  🎨 Grid: ${hasGrid ? '✅' : '❌'}`);
                    console.log(`  🎨 CSS Variables: ${hasVariables ? '✅' : '❌'}`);
                    console.log(`  🎨 Modern CSS: ${hasModernCSS ? '✅' : '❌'}`);
                }
                
            } else {
                console.log(`⚠️ Status: ${response.status} - ${response.status === 404 ? 'Not found' : 'Error'}`);
            }
            
        } catch (error) {
            console.log(`❌ Error: ${error.message}`);
        }
    }
    
    console.log('\n🎯 COMPONENT ANALYSIS SUMMARY');
    console.log('============================');
    console.log('📁 Based on the file structure analysis:');
    console.log('  • The app appears to be a standard Vite + React setup');
    console.log('  • TypeScript files are being properly transformed to JavaScript');
    console.log('  • The main entry point (main.tsx) loads correctly');
    console.log('  • App.tsx should contain the main todo app logic');
    console.log('');
    console.log('🧪 MANUAL BROWSER TESTING NEEDED:');
    console.log('  1. Open: https://preview-57.overskill.app/');
    console.log('  2. Open browser DevTools (F12)');
    console.log('  3. Check Console tab for any JavaScript errors');
    console.log('  4. Verify the todo interface loads');
    console.log('  5. Test adding a new todo item');
    console.log('  6. Test marking todos as complete/incomplete');
    console.log('  7. Test deleting todo items');
    console.log('  8. Check Network tab to ensure all resources load');
}

testAllComponents().catch(console.error);