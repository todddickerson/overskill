# Test with system python requests
puts "Testing preview URL with Python requests..."

python_test = <<~PYTHON
import requests
import sys

url = "https://preview-1.overskill.app"
print(f"Testing {url}...")

try:
    response = requests.get(url, timeout=10)
    print(f"Status: {response.status_code}")
    print(f"Content-Type: {response.headers.get('content-type')}")
    print(f"Response length: {len(response.text)} chars")
    
    if "TodoFlow" in response.text:
        print("✅ TodoFlow content found!")
    
    # Test workers.dev URL too
    workers_url = "https://preview-1.todd-e03.workers.dev"
    print(f"\\nTesting workers.dev URL: {workers_url}")
    workers_response = requests.get(workers_url, timeout=5)
    print(f"Workers.dev status: {workers_response.status_code}")
    
except Exception as e:
    print(f"Error: {type(e).__name__}: {e}")
    sys.exit(1)
PYTHON

# Write and execute the Python script
File.write('/tmp/test_preview.py', python_test)
system('python3 /tmp/test_preview.py')

# Also let's manually set the preview URL back to workers.dev for now
puts "\n\nUpdating app to use workers.dev URL for immediate testing..."
app = App.find(1)
workers_url = "https://preview-1.todd-e03.workers.dev"
app.update!(preview_url: workers_url)
puts "Preview URL updated to: #{app.preview_url}"
puts "\n✅ The preview iframe should now be working with the workers.dev URL!"