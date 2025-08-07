#!/usr/bin/env node

/**
 * Test the dev.overskill.app URL (replacement for ngrok)
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

async function testDevUrl() {
    console.log('🌐 Testing dev.overskill.app');
    console.log('============================');
    
    try {
        const response = await fetchUrl('https://dev.overskill.app/');
        
        console.log(`✅ Status: ${response.status}`);
        console.log(`📄 Content Length: ${response.data.length} bytes`);
        console.log(`🗂️ Content Type: ${response.headers['content-type']}`);
        
        // Check what kind of content we get
        const content = response.data;
        const title = content.match(/<title[^>]*>([^<]*)<\/title>/i);
        console.log(`📋 Title: ${title ? title[1] : 'Not found'}`);
        
        // Check for OverSkill app content
        const hasOverskillContent = content.toLowerCase().includes('overskill') || 
                                   content.toLowerCase().includes('todo') ||
                                   content.toLowerCase().includes('taskflow');
        
        console.log(`🎯 OverSkill Content: ${hasOverskillContent ? '✅ Found' : '❌ Not found'}`);
        
        // Show first part of content
        console.log('\n📝 Content Preview (first 300 chars):');
        console.log('-------------------------------------');
        console.log(content.substring(0, 300) + '...');
        
        if (response.status === 200) {
            console.log('\n✅ dev.overskill.app is accessible and working!');
        } else {
            console.log(`\n⚠️ dev.overskill.app returned status ${response.status}`);
        }
        
    } catch (error) {
        console.log(`❌ Error accessing dev.overskill.app: ${error.message}`);
    }
}

testDevUrl().catch(console.error);