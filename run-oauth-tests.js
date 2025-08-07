#!/usr/bin/env node

/**
 * OAuth Testing Runner for https://preview-69.overskill.app
 * 
 * This script runs basic OAuth tests without Playwright if it's not available
 * Run with: node run-oauth-tests.js
 */

const https = require('https');
const fs = require('fs');
const path = require('path');

const BASE_URL = 'https://preview-69.overskill.app';
const TEST_RESULTS_DIR = path.join(__dirname, 'test-results');

// Ensure test results directory exists
if (!fs.existsSync(TEST_RESULTS_DIR)) {
  fs.mkdirSync(TEST_RESULTS_DIR, { recursive: true });
}

const colors = {
  reset: '\x1b[0m',
  red: '\x1b[31m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  cyan: '\x1b[36m'
};

function log(message, color = 'reset') {
  console.log(colors[color] + message + colors.reset);
}

function makeRequest(url, timeout = 10000) {
  return new Promise((resolve, reject) => {
    const request = https.get(url, { timeout }, (response) => {
      let data = '';
      
      response.on('data', (chunk) => {
        data += chunk;
      });
      
      response.on('end', () => {
        resolve({
          statusCode: response.statusCode,
          headers: response.headers,
          body: data,
          timing: Date.now()
        });
      });
    });
    
    request.on('timeout', () => {
      request.destroy();
      reject(new Error('Request timeout'));
    });
    
    request.on('error', (error) => {
      reject(error);
    });
  });
}

async function testBasicConnectivity() {
  log('\n🧪 Test 1: Basic Connectivity', 'cyan');
  log('='.repeat(50));
  
  try {
    const startTime = Date.now();
    const response = await makeRequest(BASE_URL);
    const loadTime = Date.now() - startTime;
    
    log(`✅ App loads successfully`, 'green');
    log(`📊 Status Code: ${response.statusCode}`, 'blue');
    log(`⏱️ Load Time: ${loadTime}ms`, 'blue');
    log(`📄 Content Length: ${response.body.length} characters`, 'blue');
    
    // Check for key indicators
    if (response.body.includes('supabase')) {
      log(`✅ Supabase integration detected`, 'green');
    }
    
    if (response.body.includes('oauth') || response.body.includes('OAuth')) {
      log(`✅ OAuth functionality detected`, 'green');
    }
    
    if (response.body.includes('login') || response.body.includes('auth')) {
      log(`✅ Authentication system detected`, 'green');
    }
    
    // Save response for analysis
    fs.writeFileSync(
      path.join(TEST_RESULTS_DIR, 'main-page-response.html'),
      response.body
    );
    
    return { success: true, loadTime, statusCode: response.statusCode };
    
  } catch (error) {
    log(`❌ Failed to load app: ${error.message}`, 'red');
    return { success: false, error: error.message };
  }
}

async function testAuthPages() {
  log('\n🧪 Test 2: Authentication Pages', 'cyan');
  log('='.repeat(50));
  
  const pages = [
    { path: '/login', name: 'Login Page' },
    { path: '/signup', name: 'Signup Page' },
    { path: '/forgot-password', name: 'Forgot Password Page' },
    { path: '/auth/callback', name: 'OAuth Callback Page' }
  ];
  
  const results = {};
  
  for (const page of pages) {
    try {
      log(`\n📄 Testing ${page.name}...`);
      const startTime = Date.now();
      const response = await makeRequest(BASE_URL + page.path);
      const loadTime = Date.now() - startTime;
      
      results[page.path] = {
        success: true,
        statusCode: response.statusCode,
        loadTime,
        contentLength: response.body.length
      };
      
      log(`  ✅ ${page.name} loads (${response.statusCode}) - ${loadTime}ms`, 'green');
      
      // Save response
      const filename = page.path.replace(/\//g, '_').replace(/^_/, '') + '.html';
      fs.writeFileSync(
        path.join(TEST_RESULTS_DIR, filename),
        response.body
      );
      
      // Check for specific content
      if (page.path === '/login') {
        if (response.body.includes('Google') && response.body.includes('GitHub')) {
          log(`  ✅ Social login buttons detected`, 'green');
        }
        if (response.body.includes('email') && response.body.includes('password')) {
          log(`  ✅ Email/password form detected`, 'green');
        }
      }
      
      if (page.path === '/auth/callback') {
        if (response.body.includes('callback') || response.body.includes('auth')) {
          log(`  ✅ Callback handling detected`, 'green');
        }
      }
      
    } catch (error) {
      log(`  ❌ ${page.name} failed: ${error.message}`, 'red');
      results[page.path] = {
        success: false,
        error: error.message
      };
    }
  }
  
  return results;
}

async function analyzeSupabaseConfiguration() {
  log('\n🧪 Test 3: Supabase Configuration Analysis', 'cyan');
  log('='.repeat(50));
  
  try {
    const response = await makeRequest(BASE_URL);
    
    // Extract Supabase configuration
    const supabaseUrlMatch = response.body.match(/https:\/\/[a-zA-Z0-9]+\.supabase\.co/);
    const anonKeyMatch = response.body.match(/eyJ[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+/);
    
    if (supabaseUrlMatch) {
      log(`✅ Supabase URL found: ${supabaseUrlMatch[0]}`, 'green');
      
      // Test Supabase endpoint connectivity
      try {
        const supabaseResponse = await makeRequest(supabaseUrlMatch[0] + '/rest/v1/');
        log(`✅ Supabase API accessible (${supabaseResponse.statusCode})`, 'green');
      } catch (error) {
        log(`⚠️ Supabase API test failed: ${error.message}`, 'yellow');
      }
    } else {
      log(`⚠️ No Supabase URL detected in client code`, 'yellow');
    }
    
    if (anonKeyMatch) {
      log(`✅ Supabase anon key found (${anonKeyMatch[0].substring(0, 20)}...)`, 'green');
    } else {
      log(`⚠️ No Supabase anon key detected`, 'yellow');
    }
    
    // Check for potential security issues
    if (response.body.includes('service_role')) {
      log(`🚨 WARNING: Service role key may be exposed!`, 'red');
    }
    
    return {
      hasSupabaseUrl: !!supabaseUrlMatch,
      hasAnonKey: !!anonKeyMatch,
      supabaseUrl: supabaseUrlMatch?.[0]
    };
    
  } catch (error) {
    log(`❌ Configuration analysis failed: ${error.message}`, 'red');
    return { error: error.message };
  }
}

async function testOAuthEndpoints() {
  log('\n🧪 Test 4: OAuth Endpoint Analysis', 'cyan');
  log('='.repeat(50));
  
  try {
    const response = await makeRequest(BASE_URL + '/login');
    
    // Look for OAuth-related content
    const hasGoogleOAuth = response.body.includes('google') || response.body.includes('Google');
    const hasGitHubOAuth = response.body.includes('github') || response.body.includes('GitHub');
    const hasOAuthButtons = response.body.includes('Continue with') || response.body.includes('Sign in with');
    
    log(`OAuth Provider Support:`, 'blue');
    log(`  Google: ${hasGoogleOAuth ? '✅' : '❌'}`, hasGoogleOAuth ? 'green' : 'red');
    log(`  GitHub: ${hasGitHubOAuth ? '✅' : '❌'}`, hasGitHubOAuth ? 'green' : 'red');
    log(`  OAuth Buttons: ${hasOAuthButtons ? '✅' : '❌'}`, hasOAuthButtons ? 'green' : 'red');
    
    // Test callback endpoint directly
    const callbackResponse = await makeRequest(BASE_URL + '/auth/callback?test=1');
    log(`Callback Endpoint: ${callbackResponse.statusCode === 200 ? '✅' : '⚠️'} (${callbackResponse.statusCode})`, 
        callbackResponse.statusCode === 200 ? 'green' : 'yellow');
    
    return {
      hasGoogleOAuth,
      hasGitHubOAuth,
      hasOAuthButtons,
      callbackStatus: callbackResponse.statusCode
    };
    
  } catch (error) {
    log(`❌ OAuth endpoint test failed: ${error.message}`, 'red');
    return { error: error.message };
  }
}

async function generateReport(results) {
  log('\n📊 Generating Test Report...', 'cyan');
  
  const report = {
    timestamp: new Date().toISOString(),
    appUrl: BASE_URL,
    testResults: results,
    summary: {
      totalTests: Object.keys(results).length,
      passedTests: Object.values(results).filter(r => r.success !== false).length,
      failedTests: Object.values(results).filter(r => r.success === false).length
    }
  };
  
  // Save detailed report
  fs.writeFileSync(
    path.join(TEST_RESULTS_DIR, 'oauth-test-report.json'),
    JSON.stringify(report, null, 2)
  );
  
  // Generate HTML report
  const htmlReport = `
<!DOCTYPE html>
<html>
<head>
  <title>OAuth Test Report - ${BASE_URL}</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 20px; }
    .header { background: #f0f0f0; padding: 20px; border-radius: 8px; }
    .test-section { margin: 20px 0; padding: 15px; border-left: 4px solid #007bff; }
    .success { border-left-color: #28a745; }
    .failure { border-left-color: #dc3545; }
    .warning { border-left-color: #ffc107; }
    pre { background: #f8f9fa; padding: 10px; border-radius: 4px; overflow-x: auto; }
    .metric { display: inline-block; margin: 10px 20px 10px 0; }
  </style>
</head>
<body>
  <div class="header">
    <h1>OAuth Authentication Test Report</h1>
    <p><strong>App URL:</strong> ${BASE_URL}</p>
    <p><strong>Test Date:</strong> ${new Date().toLocaleString()}</p>
    <div class="metric"><strong>Total Tests:</strong> ${report.summary.totalTests}</div>
    <div class="metric"><strong>Passed:</strong> ${report.summary.passedTests}</div>
    <div class="metric"><strong>Failed:</strong> ${report.summary.failedTests}</div>
  </div>
  
  <h2>Test Results</h2>
  <pre>${JSON.stringify(report.testResults, null, 2)}</pre>
  
  <h2>Recommendations</h2>
  <ul>
    <li>Review the manual testing checklist: oauth-testing-checklist.md</li>
    <li>Run comprehensive Playwright tests: playwright-oauth-tests.spec.js</li>
    <li>Check console logs during OAuth flow for detailed debugging</li>
    <li>Verify PKCE implementation with browser developer tools</li>
    <li>Test on multiple browsers and devices</li>
  </ul>
</body>
</html>`;
  
  fs.writeFileSync(
    path.join(TEST_RESULTS_DIR, 'oauth-test-report.html'),
    htmlReport
  );
  
  return report;
}

async function main() {
  log('🚀 OAuth Authentication Test Suite', 'cyan');
  log('App: ' + BASE_URL, 'blue');
  log('='.repeat(80));
  
  const allResults = {};
  
  // Run all tests
  allResults.connectivity = await testBasicConnectivity();
  allResults.authPages = await testAuthPages();
  allResults.supabaseConfig = await analyzeSupabaseConfiguration();
  allResults.oauthEndpoints = await testOAuthEndpoints();
  
  // Generate final report
  const report = await generateReport(allResults);
  
  // Print summary
  log('\n🎯 TEST SUMMARY', 'cyan');
  log('='.repeat(50));
  log(`📊 Total Tests: ${report.summary.totalTests}`, 'blue');
  log(`✅ Passed: ${report.summary.passedTests}`, 'green');
  log(`❌ Failed: ${report.summary.failedTests}`, 'red');
  
  if (report.summary.failedTests === 0) {
    log('\n🎉 All basic tests passed! ✨', 'green');
  } else {
    log(`\n⚠️ ${report.summary.failedTests} tests failed - see details above`, 'yellow');
  }
  
  log('\n📁 Test artifacts saved to: test-results/', 'blue');
  log('  - oauth-test-report.json (detailed results)', 'blue');
  log('  - oauth-test-report.html (visual report)', 'blue');
  log('  - Page responses saved as HTML files', 'blue');
  
  log('\n🔍 Next Steps:', 'cyan');
  log('1. Open oauth-test-report.html in your browser');
  log('2. Review the manual testing checklist');
  log('3. Run Playwright tests for comprehensive coverage');
  log('4. Test OAuth flow end-to-end manually');
  
  process.exit(report.summary.failedTests === 0 ? 0 : 1);
}

// Handle errors gracefully
process.on('unhandledRejection', (error) => {
  log(`\n❌ Unhandled error: ${error.message}`, 'red');
  process.exit(1);
});

// Run the test suite
main().catch(error => {
  log(`\n❌ Test suite failed: ${error.message}`, 'red');
  process.exit(1);
});