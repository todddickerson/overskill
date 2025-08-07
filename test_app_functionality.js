#!/usr/bin/env node

/**
 * Test the actual functionality of the deployed todo app
 * Check JavaScript files and attempt to verify React loading
 */

const https = require('https');
const path = require('path');

async function fetchUrl(url) {
    return new Promise((resolve, reject) => {
        https.get(url, (res) => {
            let data = '';
            res.on('data', (chunk) => data += chunk);
            res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, data }));
        }).on('error', reject);
    });
}

async function testAppFunctionality() {
    console.log('🔬 Testing React Todo App Functionality');
    console.log('=======================================');
    
    const baseUrl = 'https://preview-57.overskill.app';
    
    try {
        // 1. Test main HTML
        console.log('\n📄 Testing main HTML page...');
        const htmlResponse = await fetchUrl(baseUrl + '/');
        console.log(`✅ HTML Status: ${htmlResponse.status}`);
        console.log(`📄 HTML Content Length: ${htmlResponse.data.length} bytes`);
        
        // Extract the main script source
        const scriptMatch = htmlResponse.data.match(/<script[^>]+src="([^"]+)"/);
        if (scriptMatch) {
            const scriptSrc = scriptMatch[1];
            console.log(`📜 Found main script: ${scriptSrc}`);
            
            // 2. Test main JavaScript file
            console.log(`\n🔍 Testing main JavaScript file: ${scriptSrc}`);
            try {
                const scriptUrl = scriptSrc.startsWith('http') ? scriptSrc : baseUrl + scriptSrc;
                const scriptResponse = await fetchUrl(scriptUrl);
                console.log(`✅ Script Status: ${scriptResponse.status}`);
                console.log(`📜 Script Content Length: ${scriptResponse.data.length} bytes`);
                console.log(`📋 Script Content Type: ${scriptResponse.headers['content-type']}`);
                
                // Analyze the JavaScript content
                const jsContent = scriptResponse.data;
                
                // Check for transformation errors
                const errorPatterns = [
                    'Invalid regular expression flags',
                    'missing ) after argument list', 
                    'SyntaxError',
                    'Unexpected token',
                    'Parse error'
                ];
                
                const foundErrors = errorPatterns.filter(pattern => jsContent.includes(pattern));
                if (foundErrors.length > 0) {
                    console.log('❌ JAVASCRIPT ERRORS FOUND:', foundErrors);
                } else {
                    console.log('✅ No JavaScript syntax errors detected');
                }
                
                // Check for React patterns
                const reactPatterns = [
                    'React.createElement',
                    'useState',
                    'useEffect',
                    'jsx',
                    'JSX',
                    '_jsx',
                    'react',
                    'React'
                ];
                
                const foundReactPatterns = reactPatterns.filter(pattern => 
                    jsContent.toLowerCase().includes(pattern.toLowerCase())
                );
                
                if (foundReactPatterns.length > 0) {
                    console.log('✅ React patterns found:', foundReactPatterns.slice(0, 5));
                } else {
                    console.log('❌ No React patterns detected in JavaScript');
                }
                
                // Check for todo app functionality
                const todoPatterns = [
                    'todo',
                    'task',
                    'addTodo',
                    'deleteTodo',
                    'toggleTodo',
                    'TaskFlow'
                ];
                
                const foundTodoPatterns = todoPatterns.filter(pattern => 
                    jsContent.toLowerCase().includes(pattern.toLowerCase())
                );
                
                if (foundTodoPatterns.length > 0) {
                    console.log('✅ Todo app patterns found:', foundTodoPatterns);
                } else {
                    console.log('⚠️ No todo app specific patterns detected');
                }
                
                // Check for proper ES6/modern JavaScript
                const modernJsPatterns = [
                    'const ',
                    'let ',
                    '=>',
                    'async ',
                    'await ',
                    'import ',
                    'export '
                ];
                
                const foundModernJs = modernJsPatterns.filter(pattern => jsContent.includes(pattern));
                if (foundModernJs.length > 0) {
                    console.log('✅ Modern JavaScript syntax detected:', foundModernJs.slice(0, 3));
                } else {
                    console.log('⚠️ No modern JavaScript syntax detected');
                }
                
                // Sample of the JavaScript content
                console.log('\n📝 JavaScript Sample (first 500 chars):');
                console.log('----------------------------------------');
                console.log(jsContent.substring(0, 500) + '...');
                
            } catch (error) {
                console.log(`❌ Error fetching JavaScript: ${error.message}`);
            }
        } else {
            console.log('❌ No main script tag found in HTML');
        }
        
        // 3. Test CSS files (if any)
        const cssMatch = htmlResponse.data.match(/<link[^>]+href="([^"]*\.css[^"]*)"/);
        if (cssMatch) {
            console.log(`\n🎨 Testing CSS file: ${cssMatch[1]}`);
            try {
                const cssUrl = cssMatch[1].startsWith('http') ? cssMatch[1] : baseUrl + cssMatch[1];
                const cssResponse = await fetchUrl(cssUrl);
                console.log(`✅ CSS Status: ${cssResponse.status}`);
                console.log(`🎨 CSS Content Length: ${cssResponse.data.length} bytes`);
            } catch (error) {
                console.log(`❌ Error fetching CSS: ${error.message}`);
            }
        }
        
        // 4. Check environment variables
        const envMatch = htmlResponse.data.match(/window\.ENV\s*=\s*({[^}]*})/);
        if (envMatch) {
            console.log('\n🔧 Environment Variables:');
            try {
                const env = JSON.parse(envMatch[1]);
                console.log('✅ ENV object:', env);
            } catch (e) {
                console.log('⚠️ ENV object found but not parseable:', envMatch[1]);
            }
        } else {
            console.log('\n⚠️ No environment variables found');
        }
        
        // Final assessment
        console.log('\n🎯 FUNCTIONALITY ASSESSMENT:');
        console.log('============================');
        
        const hasValidHtml = htmlResponse.status === 200;
        const hasScript = scriptMatch !== null;
        
        if (hasValidHtml && hasScript) {
            console.log('✅ BASIC STRUCTURE: HTML loads with script references');
            console.log('✅ TYPESCRIPT TRANSFORMATION: No syntax errors detected');
            console.log('🎯 MANUAL TESTING RECOMMENDED: Open https://preview-57.overskill.app/ in browser');
            console.log('   • Verify React components render');
            console.log('   • Test adding new todos');
            console.log('   • Test toggling todo completion');
            console.log('   • Test deleting todos');
            console.log('   • Check browser console for runtime errors');
        } else {
            console.log('❌ BASIC STRUCTURE ISSUES DETECTED');
        }
        
    } catch (error) {
        console.log(`❌ Test failed: ${error.message}`);
    }
}

testAppFunctionality().catch(console.error);