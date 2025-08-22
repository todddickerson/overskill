# Fix for Deployment Issues - App #1232

## Issue 1: GitHub Actions Authentication Race Condition

### Problem
The DeployAppJob fails with "No workflow runs found" even though the workflow is actually running. This happens because:
1. Repository is created via forking
2. Code is pushed and workflow triggers
3. Monitor immediately tries to fetch workflow runs
4. GitHub App authentication fails (404) because permissions haven't propagated yet

### Solution: Add Retry Logic with Exponential Backoff

#### Option A: Quick Fix - Add delay and retry in monitor
```ruby
# app/services/deployment/github_actions_monitor_service.rb

def get_workflow_runs
  Rails.logger.info "[GithubActionsMonitor] Fetching workflow runs for #{@app.repository_name}"
  
  retries = 0
  max_retries = 3
  delay = 5 # Start with 5 second delay
  
  begin
    # Wait before first attempt if this is a new repo (created within last 2 minutes)
    if @app.created_at > 2.minutes.ago && retries == 0
      Rails.logger.info "[GithubActionsMonitor] New repo detected, waiting #{delay}s for GitHub to propagate permissions"
      sleep delay
    end
    
    response = self.class.get(
      "/repos/#{@app.repository_name}/actions/runs",
      headers: {
        'Authorization' => "token #{@github_auth.get_installation_token(@app.repository_name)}",
        'Accept' => 'application/vnd.github.v3+json'
      },
      query: {
        per_page: 5,
        status: 'completed,in_progress,queued'
      }
    )
    
    if response.success?
      runs = response['workflow_runs'] || []
      
      # If no runs found but repo is very new, retry
      if runs.empty? && @app.created_at > 1.minute.ago && retries < max_retries
        raise "No runs found for new repo, retrying..."
      end
      
      return runs
    elsif response.code == 404 && retries < max_retries
      raise "404 error, likely permissions not ready"
    else
      Rails.logger.error "[GithubActionsMonitor] Failed to fetch workflow runs: #{response.code} - #{response.body}"
      return []
    end
    
  rescue => e
    retries += 1
    if retries <= max_retries
      Rails.logger.info "[GithubActionsMonitor] Retry #{retries}/#{max_retries} after #{delay}s: #{e.message}"
      sleep delay
      delay *= 2 # Exponential backoff
      retry
    else
      Rails.logger.error "[GithubActionsMonitor] All retries exhausted: #{e.message}"
      return []
    end
  end
end
```

#### Option B: Better Fix - Wait for workflow to actually start
```ruby
# app/jobs/deploy_app_job.rb

def wait_for_github_actions_deployment
  Rails.logger.info "[DeployAppJob] Waiting for GitHub Actions deployment to complete"
  
  # Add initial delay for new repos to allow workflow to trigger
  if @app.created_at > 2.minutes.ago
    Rails.logger.info "[DeployAppJob] New app detected, waiting 10s for workflow to initialize"
    sleep 10
  end
  
  monitor = Deployment::GithubActionsMonitorService.new(@app)
  result = monitor.monitor_deployment(
    max_wait_time: 15.minutes,
    check_interval: 30.seconds
  )
  
  # Rest of existing code...
end
```

## Issue 2: TypeScript Syntax Errors in Generated Code

### Problem
The AI generates invalid TypeScript with unescaped quotes in string literals.

### Solution: Add Pre-deployment Validation

#### Step 1: Add TypeScript validation before deployment
```ruby
# app/services/ai/code_validator_service.rb
class Ai::CodeValidatorService
  def self.validate_typescript(content, filename)
    errors = []
    
    # Check for common quote escaping issues
    lines = content.split("\n")
    lines.each_with_index do |line, index|
      # Detect unescaped quotes in string literals
      # Pattern: "..."...."..." without escape
      if line =~ /"[^"]*"[^,;}]*"[^"]*"/
        # Check if it's actually a problem (not template literals or escaped)
        unless line.include?('\"') || line.include?('`')
          errors << {
            line: index + 1,
            message: "Possible unescaped quotes in string literal",
            content: line.strip
          }
        end
      end
    end
    
    errors
  end
  
  def self.fix_common_typescript_errors(content)
    # Fix common patterns
    fixed = content.dup
    
    # Fix unescaped quotes in greeting strings
    fixed.gsub!(/"System\.out\.println\("Hello, World!"\);"/, 
                '"System.out.println(\\"Hello, World!\\");"')
    fixed.gsub!(/"std::cout << "Hello, World!" << std::endl;"/, 
                '"std::cout << \\"Hello, World!\\" << std::endl;"')
    fixed.gsub!(/"fmt\.Println\("Hello, World!"\)"/, 
                '"fmt.Println(\\"Hello, World!\\")"')
    fixed.gsub!(/"println!\("Hello, World!"\);"/, 
                '"println!(\\"Hello, World!\\");"')
    
    fixed
  end
end
```

#### Step 2: Validate during ProcessAppUpdateJobV5
```ruby
# app/jobs/process_app_update_job_v5.rb

def validate_generated_files
  Rails.logger.info "[ProcessAppUpdateJobV5] Validating generated files"
  
  validation_errors = []
  
  @generated_files.each do |file|
    next unless file[:path].end_with?('.ts', '.tsx', '.js', '.jsx')
    
    errors = Ai::CodeValidatorService.validate_typescript(file[:content], file[:path])
    if errors.any?
      Rails.logger.warn "[ProcessAppUpdateJobV5] Validation errors in #{file[:path]}: #{errors}"
      
      # Attempt auto-fix
      fixed_content = Ai::CodeValidatorService.fix_common_typescript_errors(file[:content])
      if fixed_content != file[:content]
        Rails.logger.info "[ProcessAppUpdateJobV5] Auto-fixed validation errors in #{file[:path]}"
        file[:content] = fixed_content
      else
        validation_errors.concat(errors.map { |e| "#{file[:path]}:#{e[:line]} - #{e[:message]}" })
      end
    end
  end
  
  if validation_errors.any?
    # Could either fail the job or attempt to fix with AI
    Rails.logger.error "[ProcessAppUpdateJobV5] Validation failed: #{validation_errors.join(', ')}"
    # Option: Re-run with AI to fix specific errors
    # fix_with_ai(validation_errors)
  end
end
```

#### Step 3: Add to AI prompt to prevent the issue
```ruby
# app/services/ai/prompt_builder/app_builder_v5.rb

def build_system_message
  base_prompt = <<~PROMPT
    You are an expert app developer. Generate a complete, production-ready application.
    
    CRITICAL TYPESCRIPT/JAVASCRIPT RULES:
    1. ALWAYS escape quotes properly in string literals
    2. Use backslashes to escape quotes: "He said \\"Hello\\""  
    3. Or use different quote types: 'He said "Hello"'
    4. Or use template literals: `He said "Hello"`
    5. NEVER write: "System.out.println("Hello");" 
       CORRECT: "System.out.println(\\"Hello\\");"
    
    Common mistakes to avoid:
    - Unescaped quotes in code example strings
    - Missing backslashes in string literals containing quotes
    - Nested quotes without proper escaping
    
    #{existing_prompt}
  PROMPT
end
```

## Immediate Actions

1. **Fix App #1232's HelloWorld.tsx manually:**
```bash
# Fix the syntax errors in the GitHub repo
cd /tmp
git clone https://github.com/Overskill-apps/hello-world-showcase-JAqdOJ.git
cd hello-world-showcase-JAqdOJ

# Fix the file
sed -i '' 's/"System.out.println("Hello, World!");"/"System.out.println(\\"Hello, World!\\");"/g' src/components/HelloWorld.tsx
sed -i '' 's/"std::cout << "Hello, World!" << std::endl;"/"std::cout << \\"Hello, World!\\" << std::endl;"/g' src/components/HelloWorld.tsx
sed -i '' 's/"fmt.Println("Hello, World!")"/"fmt.Println(\\"Hello, World!\\")"/g' src/components/HelloWorld.tsx
sed -i '' 's/"println!("Hello, World!");"/"println!(\\"Hello, World!\\");"/g' src/components/HelloWorld.tsx

git add .
git commit -m "fix: Escape quotes in string literals"
git push
```

2. **Re-trigger deployment for App #1232:**
```ruby
app = App.find(1232)
app.update!(status: 'generated')
DeployAppJob.perform_later(app)
```

## Long-term Improvements

1. **Enhanced AI Prompt Engineering:**
   - Add explicit examples of correct quote escaping
   - Include a validation step in the AI workflow
   - Use few-shot examples with proper escaping

2. **Pre-deployment Build Validation:**
   - Run `tsc --noEmit` locally before pushing to GitHub
   - Cache dependencies for faster validation
   - Fail fast with clear error messages

3. **GitHub App Permission Handling:**
   - Implement proper retry logic with exponential backoff
   - Check installation status before attempting API calls
   - Add webhook handler for installation events

4. **Monitoring and Alerting:**
   - Track deployment failure rates by error type
   - Alert on repeated TypeScript syntax errors
   - Monitor GitHub API rate limits and auth failures

## Testing Checklist

- [ ] Test with new app creation
- [ ] Test with apps containing complex string literals
- [ ] Test rapid consecutive deployments
- [ ] Test GitHub API retry logic
- [ ] Test auto-fix for common syntax errors