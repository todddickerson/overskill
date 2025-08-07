// Global teardown for OAuth tests
async function globalTeardown() {
  console.log('🧹 Cleaning up OAuth authentication tests...');
  
  const fs = require('fs');
  const path = require('path');
  
  // Generate final summary report
  const resultsDir = path.join(__dirname, 'test-results');
  
  try {
    // Check if we have test results
    const playwrightResults = path.join(resultsDir, 'playwright-results.json');
    const basicResults = path.join(resultsDir, 'oauth-test-report.json');
    
    let summary = {
      timestamp: new Date().toISOString(),
      testTypes: []
    };
    
    if (fs.existsSync(playwrightResults)) {
      const data = JSON.parse(fs.readFileSync(playwrightResults, 'utf8'));
      summary.testTypes.push({
        type: 'Playwright Tests',
        total: data.stats?.total || 0,
        passed: data.stats?.passed || 0,
        failed: data.stats?.failed || 0,
        skipped: data.stats?.skipped || 0
      });
    }
    
    if (fs.existsSync(basicResults)) {
      const data = JSON.parse(fs.readFileSync(basicResults, 'utf8'));
      summary.testTypes.push({
        type: 'Basic Connectivity Tests',
        results: data.summary
      });
    }
    
    // Save combined summary
    fs.writeFileSync(
      path.join(resultsDir, 'final-test-summary.json'),
      JSON.stringify(summary, null, 2)
    );
    
    console.log('📊 Test Summary Generated');
    console.log(`📁 All results saved to: ${resultsDir}`);
    
  } catch (error) {
    console.log(`⚠️ Error generating summary: ${error.message}`);
  }
  
  return Promise.resolve();
}

module.exports = globalTeardown;