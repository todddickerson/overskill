// Global setup for OAuth tests
async function globalSetup() {
  console.log('🚀 Setting up OAuth authentication tests...');
  
  // Create test results directory
  const fs = require('fs');
  const path = require('path');
  
  const resultsDir = path.join(__dirname, 'test-results');
  if (!fs.existsSync(resultsDir)) {
    fs.mkdirSync(resultsDir, { recursive: true });
  }
  
  // Log test environment
  console.log(`📊 Test Environment:`);
  console.log(`  - App URL: https://preview-69.overskill.app`);
  console.log(`  - Results dir: ${resultsDir}`);
  console.log(`  - Timestamp: ${new Date().toISOString()}`);
  
  return Promise.resolve();
}

module.exports = globalSetup;