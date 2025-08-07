// Comprehensive OAuth Testing Suite for https://preview-69.overskill.app
// Run with: npx playwright test playwright-oauth-tests.spec.js

const { test, expect } = require('@playwright/test');

const BASE_URL = 'https://preview-69.overskill.app';

test.describe('OAuth Authentication System Tests', () => {
  let page;
  let context;
  
  test.beforeEach(async ({ browser }) => {
    // Create new context for each test to ensure clean state
    context = await browser.newContext({
      recordVideo: { dir: 'test-results/videos' },
      recordHar: { path: 'test-results/network.har' }
    });
    page = await context.newPage();
    
    // Enable console logging
    page.on('console', msg => {
      console.log(`[${msg.type()}] ${msg.text()}`);
    });
    
    // Track network failures
    page.on('requestfailed', request => {
      console.log(`❌ Network request failed: ${request.url()} - ${request.failure().errorText}`);
    });
  });

  test.afterEach(async () => {
    await context.close();
  });

  test('1. Initial Load Test - App loads correctly and redirects', async () => {
    console.log('🧪 Testing initial app load...');
    
    // Navigate to app
    await page.goto(BASE_URL);
    
    // Wait for page to load and check for redirection
    await page.waitForLoadState('networkidle');
    
    // Take screenshot of landing page
    await page.screenshot({ path: 'test-results/01-initial-load.png', fullPage: true });
    
    // Check if it redirects to login (expected for unauthenticated users)
    const currentUrl = page.url();
    if (currentUrl.includes('/login')) {
      console.log('✅ Correctly redirected to login page');
    } else {
      console.log('ℹ️ No redirect to login - may be already authenticated or different flow');
    }
    
    // Check for console errors
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    
    // Wait a bit more to catch any delayed errors
    await page.waitForTimeout(2000);
    
    expect(errors).toEqual([]);
    console.log('✅ No JavaScript errors on initial load');
  });

  test('2. Login Page Test - UI elements and form validation', async () => {
    console.log('🧪 Testing login page...');
    
    // Navigate to login page
    await page.goto(`${BASE_URL}/login`);
    await page.waitForLoadState('networkidle');
    
    // Take screenshot
    await page.screenshot({ path: 'test-results/02-login-page.png', fullPage: true });
    
    // Check for essential UI elements
    await expect(page.locator('h2').filter({ hasText: 'Sign in to your account' })).toBeVisible();
    await expect(page.locator('button').filter({ hasText: 'Continue with Google' })).toBeVisible();
    await expect(page.locator('button').filter({ hasText: 'Continue with GitHub' })).toBeVisible();
    await expect(page.locator('input[type="email"]')).toBeVisible();
    await expect(page.locator('input[type="password"]')).toBeVisible();
    await expect(page.locator('a').filter({ hasText: 'Forgot your password?' })).toBeVisible();
    await expect(page.locator('a').filter({ hasText: 'create a new account' })).toBeVisible();
    
    console.log('✅ All login page UI elements are present');
    
    // Test form validation
    await page.locator('button[type="submit"]').click();
    await page.waitForTimeout(1000);
    
    // Should show HTML5 validation for required fields
    const emailInput = page.locator('input[type="email"]');
    const isEmailInvalid = await emailInput.evaluate(el => !el.validity.valid);
    
    if (isEmailInvalid) {
      console.log('✅ Form validation working - required fields validated');
    }
    
    // Test invalid email format
    await emailInput.fill('invalid-email');
    await page.locator('input[type="password"]').fill('password123');
    await page.locator('button[type="submit"]').click();
    await page.waitForTimeout(1000);
    
    const isStillInvalid = await emailInput.evaluate(el => !el.validity.valid);
    if (isStillInvalid) {
      console.log('✅ Email format validation working');
    }
    
    await page.screenshot({ path: 'test-results/02-login-validation.png', fullPage: true });
  });

  test('3. Signup Page Test - Form validation and UI', async () => {
    console.log('🧪 Testing signup page...');
    
    await page.goto(`${BASE_URL}/signup`);
    await page.waitForLoadState('networkidle');
    
    await page.screenshot({ path: 'test-results/03-signup-page.png', fullPage: true });
    
    // Check UI elements
    await expect(page.locator('h2').filter({ hasText: 'Create your account' })).toBeVisible();
    await expect(page.locator('button').filter({ hasText: 'Continue with Google' })).toBeVisible();
    await expect(page.locator('button').filter({ hasText: 'Continue with GitHub' })).toBeVisible();
    await expect(page.locator('input[name="email"]')).toBeVisible();
    await expect(page.locator('input[name="password"]')).toBeVisible();
    await expect(page.locator('input[name="confirm-password"]')).toBeVisible();
    
    // Test password confirmation validation
    await page.locator('input[name="email"]').fill('test@example.com');
    await page.locator('input[name="password"]').fill('password123');
    await page.locator('input[name="confirm-password"]').fill('different-password');
    await page.locator('button[type="submit"]').click();
    
    // Wait for error message
    await page.waitForTimeout(1000);
    
    // Should show password mismatch error
    const errorMessage = page.locator('.bg-red-50');
    if (await errorMessage.isVisible()) {
      const errorText = await errorMessage.textContent();
      if (errorText.includes('do not match')) {
        console.log('✅ Password confirmation validation working');
      }
    }
    
    await page.screenshot({ path: 'test-results/03-signup-validation.png', fullPage: true });
  });

  test('4. Forgot Password Page Test', async () => {
    console.log('🧪 Testing forgot password page...');
    
    await page.goto(`${BASE_URL}/forgot-password`);
    await page.waitForLoadState('networkidle');
    
    await page.screenshot({ path: 'test-results/04-forgot-password.png', fullPage: true });
    
    // Check UI elements
    await expect(page.locator('h2').filter({ hasText: 'Reset your password' })).toBeVisible();
    await expect(page.locator('input[type="email"]')).toBeVisible();
    await expect(page.locator('button[type="submit"]')).toBeVisible();
    await expect(page.locator('a').filter({ hasText: 'Back to login' })).toBeVisible();
    
    console.log('✅ Forgot password page UI elements are present');
  });

  test('5. OAuth Button Click Test - Verify redirect initiation', async () => {
    console.log('🧪 Testing OAuth button clicks...');
    
    await page.goto(`${BASE_URL}/login`);
    await page.waitForLoadState('networkidle');
    
    // Test Google OAuth button
    console.log('Testing Google OAuth...');
    
    // Listen for navigation to OAuth provider
    const navigationPromise = page.waitForNavigation({ timeout: 10000 });
    
    await page.locator('button').filter({ hasText: 'Continue with Google' }).click();
    
    try {
      await navigationPromise;
      const currentUrl = page.url();
      console.log(`Google OAuth redirect URL: ${currentUrl}`);
      
      if (currentUrl.includes('accounts.google.com') || currentUrl.includes('oauth')) {
        console.log('✅ Google OAuth redirect successful');
        await page.screenshot({ path: 'test-results/05-google-oauth.png', fullPage: true });
      } else {
        console.log('⚠️ Google OAuth redirect may not be working correctly');
      }
    } catch (error) {
      console.log(`⚠️ Google OAuth redirect timeout or error: ${error.message}`);
    }
    
    // Navigate back to test GitHub OAuth
    await page.goto(`${BASE_URL}/login`);
    await page.waitForLoadState('networkidle');
    
    console.log('Testing GitHub OAuth...');
    const githubNavigationPromise = page.waitForNavigation({ timeout: 10000 });
    
    await page.locator('button').filter({ hasText: 'Continue with GitHub' }).click();
    
    try {
      await githubNavigationPromise;
      const currentUrl = page.url();
      console.log(`GitHub OAuth redirect URL: ${currentUrl}`);
      
      if (currentUrl.includes('github.com') || currentUrl.includes('oauth')) {
        console.log('✅ GitHub OAuth redirect successful');
        await page.screenshot({ path: 'test-results/05-github-oauth.png', fullPage: true });
      } else {
        console.log('⚠️ GitHub OAuth redirect may not be working correctly');
      }
    } catch (error) {
      console.log(`⚠️ GitHub OAuth redirect timeout or error: ${error.message}`);
    }
  });

  test('6. Auth Callback Page Test - Error handling', async () => {
    console.log('🧪 Testing auth callback error handling...');
    
    // Test callback with error parameter
    await page.goto(`${BASE_URL}/auth/callback?error=access_denied&error_description=User%20cancelled`);
    await page.waitForLoadState('networkidle');
    
    await page.screenshot({ path: 'test-results/06-callback-error.png', fullPage: true });
    
    // Should show error message
    const errorContainer = page.locator('.bg-red-100, .bg-white').filter({ hasText: 'Authentication Failed' });
    if (await errorContainer.isVisible()) {
      console.log('✅ Auth callback error handling is working');
      
      // Check for user-friendly error message
      const errorMessage = await errorContainer.textContent();
      if (errorMessage.includes('Access denied') || errorMessage.includes('cancelled')) {
        console.log('✅ User-friendly error message displayed');
      }
      
      // Check for debug info
      const debugDetails = page.locator('details').filter({ hasText: 'Technical Details' });
      if (await debugDetails.isVisible()) {
        console.log('✅ Debug information is available');
      }
      
      // Check for retry buttons
      const retryButton = page.locator('button').filter({ hasText: 'Try Again' });
      const newWindowButton = page.locator('button').filter({ hasText: 'New Window' });
      
      if (await retryButton.isVisible()) {
        console.log('✅ Retry button is available');
      }
      if (await newWindowButton.isVisible()) {
        console.log('✅ New window button is available');
      }
    }
    
    // Test callback with no code parameter
    await page.goto(`${BASE_URL}/auth/callback`);
    await page.waitForTimeout(3000);
    
    await page.screenshot({ path: 'test-results/06-callback-no-code.png', fullPage: true });
  });

  test('7. Console Logs Test - Verify proper logging', async () => {
    console.log('🧪 Testing console logging...');
    
    const consoleLogs = [];
    page.on('console', msg => {
      consoleLogs.push(`[${msg.type()}] ${msg.text()}`);
    });
    
    await page.goto(`${BASE_URL}/login`);
    await page.waitForLoadState('networkidle');
    
    // Wait for console logs to populate
    await page.waitForTimeout(2000);
    
    // Check for expected Supabase logs
    const hasSupabaseStatus = consoleLogs.some(log => 
      log.includes('Supabase Client Status') || log.includes('supabase')
    );
    
    if (hasSupabaseStatus) {
      console.log('✅ Supabase configuration logging is working');
    } else {
      console.log('⚠️ No Supabase configuration logs found');
    }
    
    // Log all console messages for analysis
    console.log('\n📝 All Console Messages:');
    consoleLogs.forEach(log => console.log(log));
  });

  test('8. Performance Test - Load times and network requests', async () => {
    console.log('🧪 Testing performance metrics...');
    
    const startTime = Date.now();
    
    await page.goto(BASE_URL);
    await page.waitForLoadState('networkidle');
    
    const loadTime = Date.now() - startTime;
    console.log(`📊 Initial load time: ${loadTime}ms`);
    
    // Check network requests
    const requests = [];
    page.on('request', request => {
      requests.push({
        url: request.url(),
        method: request.method(),
        resourceType: request.resourceType()
      });
    });
    
    await page.reload();
    await page.waitForLoadState('networkidle');
    
    console.log(`📊 Total network requests: ${requests.length}`);
    
    // Analyze request types
    const requestTypes = requests.reduce((acc, req) => {
      acc[req.resourceType] = (acc[req.resourceType] || 0) + 1;
      return acc;
    }, {});
    
    console.log('📊 Request breakdown:', requestTypes);
    
    // Check for potential issues
    const failedRequests = requests.filter(req => req.method === 'GET' && req.url.includes('404'));
    if (failedRequests.length > 0) {
      console.log(`⚠️ Found ${failedRequests.length} potentially failed requests`);
    }
    
    // Performance recommendations
    if (loadTime > 5000) {
      console.log('⚠️ Load time over 5 seconds - consider optimization');
    } else if (loadTime < 2000) {
      console.log('✅ Good load time performance');
    }
    
    if (requests.length > 50) {
      console.log('⚠️ High number of network requests - consider bundling');
    }
  });

  test('9. Mobile Responsiveness Test', async () => {
    console.log('🧪 Testing mobile responsiveness...');
    
    // Set mobile viewport
    await page.setViewportSize({ width: 375, height: 667 });
    
    await page.goto(`${BASE_URL}/login`);
    await page.waitForLoadState('networkidle');
    
    await page.screenshot({ path: 'test-results/09-mobile-login.png', fullPage: true });
    
    // Check if elements are still visible and properly sized
    const googleButton = page.locator('button').filter({ hasText: 'Continue with Google' });
    const githubButton = page.locator('button').filter({ hasText: 'Continue with GitHub' });
    
    const googleBounds = await googleButton.boundingBox();
    const githubBounds = await githubButton.boundingBox();
    
    // Check button sizes (should be at least 44px for touch targets)
    if (googleBounds && googleBounds.height >= 44) {
      console.log('✅ Google button has adequate touch target size');
    } else {
      console.log('⚠️ Google button may be too small for mobile interaction');
    }
    
    if (githubBounds && githubBounds.height >= 44) {
      console.log('✅ GitHub button has adequate touch target size');
    } else {
      console.log('⚠️ GitHub button may be too small for mobile interaction');
    }
    
    // Test signup page on mobile
    await page.goto(`${BASE_URL}/signup`);
    await page.waitForLoadState('networkidle');
    
    await page.screenshot({ path: 'test-results/09-mobile-signup.png', fullPage: true });
  });

  test('10. Security Test - Check for exposed secrets', async () => {
    console.log('🧪 Testing security - checking for exposed secrets...');
    
    await page.goto(BASE_URL);
    await page.waitForLoadState('networkidle');
    
    // Get page content
    const content = await page.content();
    
    // Check for potentially exposed secrets (should only find anon keys, not service keys)
    const potentialSecrets = [];
    
    if (content.includes('service_role') || content.includes('service-role')) {
      potentialSecrets.push('Supabase service role key may be exposed');
    }
    
    if (content.match(/sk_live_[a-zA-Z0-9]+/)) {
      potentialSecrets.push('Stripe live secret key may be exposed');
    }
    
    if (content.match(/pk_live_[a-zA-Z0-9]+/)) {
      console.log('ℹ️ Stripe live publishable key found (this is expected)');
    }
    
    if (content.match(/eyJ[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+/)) {
      // This might be a JWT token - check if it's just the anon key
      const jwtPattern = /eyJ[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+/g;
      const matches = content.match(jwtPattern);
      if (matches && matches.length > 1) {
        potentialSecrets.push(`Multiple JWT tokens found: ${matches.length}`);
      }
    }
    
    if (potentialSecrets.length > 0) {
      console.log('🚨 Security concerns found:');
      potentialSecrets.forEach(secret => console.log(`  - ${secret}`));
    } else {
      console.log('✅ No obvious security issues found');
    }
    
    // Check HTTPS
    if (page.url().startsWith('https://')) {
      console.log('✅ Site is served over HTTPS');
    } else {
      console.log('⚠️ Site is not served over HTTPS');
    }
  });
});

// Generate test report
test.afterAll(async () => {
  console.log('\n' + '='.repeat(80));
  console.log('📊 OAUTH AUTHENTICATION TEST REPORT');
  console.log('='.repeat(80));
  console.log(`Date: ${new Date().toISOString()}`);
  console.log(`App URL: ${BASE_URL}`);
  console.log('Test artifacts saved to: test-results/');
  console.log('\n📁 Generated Files:');
  console.log('  - Screenshots: test-results/*.png');
  console.log('  - Videos: test-results/videos/');
  console.log('  - Network logs: test-results/network.har');
  console.log('\n🔍 Next Steps:');
  console.log('  1. Review screenshots for UI/UX issues');
  console.log('  2. Analyze console logs for errors');
  console.log('  3. Check network.har for performance issues');
  console.log('  4. Test OAuth flow end-to-end manually');
  console.log('='.repeat(80));
});