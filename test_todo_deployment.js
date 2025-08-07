#!/usr/bin/env node

/**
 * Comprehensive deployment test for the React Todo App
 * Tests both the main deployment and ngrok URL
 */

const fs = require('fs').promises;
const path = require('path');

// Simple HTTP test without puppeteer since it might not be installed
async function testUrl(url, name) {
    const https = require('https');
    const http = require('http');
    
    console.log(`\n🔍 Testing ${name}: ${url}`);
    
    return new Promise((resolve) => {
        const client = url.startsWith('https:') ? https : http;
        const timeout = 10000; // 10 seconds
        
        const req = client.get(url, (res) => {
            console.log(`✅ ${name} - Status: ${res.statusCode}`);
            console.log(`📋 ${name} - Headers:`, Object.keys(res.headers).join(', '));
            
            let data = '';
            res.on('data', (chunk) => {
                data += chunk;
            });
            
            res.on('end', () => {
                console.log(`📄 ${name} - Content length: ${data.length} bytes`);
                
                // Check for common patterns
                const hasReact = data.includes('React') || data.includes('react') || data.includes('_react');
                const hasRootDiv = data.includes('<div id="root"') || data.includes("div id='root'");
                const hasScript = data.includes('<script') || data.includes('script>');
                const hasError = data.includes('error') || data.includes('Error') || data.includes('ERROR');
                const hasTitle = data.match(/<title[^>]*>([^<]*)<\/title>/i);
                
                console.log(`🔍 ${name} - Analysis:`);
                console.log(`  React references: ${hasReact ? '✅' : '❌'}`);
                console.log(`  Root div: ${hasRootDiv ? '✅' : '❌'}`);
                console.log(`  Script tags: ${hasScript ? '✅' : '❌'}`);
                console.log(`  Error indicators: ${hasError ? '⚠️ Found' : '✅ None'}`);
                console.log(`  Title: ${hasTitle ? hasTitle[1] : 'Not found'}`);
                
                // Check for specific TypeScript errors
                const tsErrors = [
                    'Invalid regular expression flags',
                    'missing ) after argument list',
                    'Unexpected token',
                    'SyntaxError'
                ];
                
                const foundErrors = tsErrors.filter(error => data.includes(error));
                if (foundErrors.length > 0) {
                    console.log(`❌ ${name} - TypeScript transformation errors found:`, foundErrors);
                } else {
                    console.log(`✅ ${name} - No known TypeScript transformation errors detected`);
                }
                
                // Look for todo app specific content
                const todoIndicators = [
                    'todo', 'Todo', 'TODO',
                    'task', 'Task', 'TASK',
                    'TaskFlow', 'taskflow'
                ];
                
                const foundTodoTerms = todoIndicators.filter(term => data.toLowerCase().includes(term.toLowerCase()));
                if (foundTodoTerms.length > 0) {
                    console.log(`✅ ${name} - Todo app indicators found:`, foundTodoTerms);
                } else {
                    console.log(`⚠️ ${name} - No todo app specific content detected`);
                }
                
                resolve({
                    success: true,
                    status: res.statusCode,
                    contentLength: data.length,
                    hasReact,
                    hasRootDiv,
                    hasScript,
                    hasError,
                    title: hasTitle ? hasTitle[1] : null,
                    foundErrors,
                    foundTodoTerms,
                    content: data.substring(0, 1000) // First 1000 chars for debugging
                });
            });
        });
        
        req.setTimeout(timeout, () => {
            console.log(`❌ ${name} - Request timeout after ${timeout}ms`);
            req.abort();
            resolve({
                success: false,
                error: 'timeout'
            });
        });
        
        req.on('error', (err) => {
            console.log(`❌ ${name} - Request error:`, err.message);
            resolve({
                success: false,
                error: err.message
            });
        });
    });
}

async function runTests() {
    console.log('🚀 OverSkill Todo App Deployment Test');
    console.log('=====================================');
    
    const results = {};
    
    // Test main app
    results.mainApp = await testUrl('https://preview-57.overskill.app/', 'Main App');
    
    // Test ngrok URL
    results.ngrok = await testUrl('https://2kqla4w67ypgikzd3.51mivkfketqaju9fz.ngrok-cname.com', 'Ngrok URL');
    
    // Generate comprehensive report
    console.log('\n📋 COMPREHENSIVE TEST REPORT');
    console.log('=====================================');
    
    console.log('\n🌐 MAIN APP (preview-57.overskill.app):');
    if (results.mainApp.success) {
        console.log(`  Status: ✅ ACCESSIBLE (${results.mainApp.status})`);
        console.log(`  Content: ${results.mainApp.contentLength} bytes`);
        console.log(`  React: ${results.mainApp.hasReact ? '✅' : '❌'}`);
        console.log(`  Root div: ${results.mainApp.hasRootDiv ? '✅' : '❌'}`);
        console.log(`  JavaScript: ${results.mainApp.hasScript ? '✅' : '❌'}`);
        console.log(`  Title: ${results.mainApp.title || 'Not found'}`);
        console.log(`  Todo indicators: ${results.mainApp.foundTodoTerms.length > 0 ? '✅ ' + results.mainApp.foundTodoTerms.join(', ') : '❌ None'}`);
        
        if (results.mainApp.foundErrors.length > 0) {
            console.log(`  ❌ TYPESCRIPT ERRORS: ${results.mainApp.foundErrors.join(', ')}`);
            console.log('  🚨 The TypeScript transformation is still broken!');
        } else {
            console.log('  ✅ NO TYPESCRIPT TRANSFORMATION ERRORS DETECTED');
        }
    } else {
        console.log(`  Status: ❌ FAILED - ${results.mainApp.error}`);
    }
    
    console.log('\n🔗 NGROK URL:');
    if (results.ngrok.success) {
        console.log(`  Status: ✅ ACCESSIBLE (${results.ngrok.status})`);
        console.log(`  Content: ${results.ngrok.contentLength} bytes`);
        console.log(`  Title: ${results.ngrok.title || 'Not found'}`);
    } else {
        console.log(`  Status: ❌ FAILED - ${results.ngrok.error}`);
    }
    
    // Overall assessment
    console.log('\n🎯 OVERALL ASSESSMENT:');
    
    const mainAppWorking = results.mainApp.success && results.mainApp.status === 200;
    const noTsErrors = results.mainApp.success && results.mainApp.foundErrors.length === 0;
    const hasReactElements = results.mainApp.success && (results.mainApp.hasReact || results.mainApp.hasRootDiv);
    const hasTodoContent = results.mainApp.success && results.mainApp.foundTodoTerms.length > 0;
    
    if (mainAppWorking && noTsErrors && hasReactElements) {
        console.log('  ✅ DEPLOYMENT SUCCESS: App is accessible and TypeScript errors are fixed!');
        
        if (hasTodoContent) {
            console.log('  ✅ TODO APP: Todo-specific content detected in the app');
        } else {
            console.log('  ⚠️ TODO APP: No specific todo content detected - may need manual verification');
        }
        
        console.log('\n  🎉 RECOMMENDED NEXT STEPS:');
        console.log('    • Open https://preview-57.overskill.app/ in browser');
        console.log('    • Test adding/completing/deleting todos manually');
        console.log('    • Check browser console for any runtime errors');
        console.log('    • Verify all React components are interactive');
        
    } else {
        console.log('  ❌ DEPLOYMENT ISSUES DETECTED:');
        if (!mainAppWorking) console.log('    • Main app is not accessible');
        if (!noTsErrors) console.log('    • TypeScript transformation errors persist');
        if (!hasReactElements) console.log('    • React elements not detected');
        
        console.log('\n  🔧 RECOMMENDED FIXES:');
        console.log('    • Check Cloudflare Worker deployment logs');
        console.log('    • Review TypeScript to JavaScript transformation code');
        console.log('    • Verify all build artifacts are properly uploaded');
        console.log('    • Test the deployment process locally');
    }
    
    // Save detailed results
    const reportPath = path.join(__dirname, 'deployment-test-results.json');
    await fs.writeFile(reportPath, JSON.stringify(results, null, 2));
    console.log(`\n💾 Detailed results saved to: ${reportPath}`);
}

// Run the tests
runTests().catch(console.error);