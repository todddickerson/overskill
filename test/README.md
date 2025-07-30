# OverSkill Test Suite

This test suite follows Rails 8 and BulletTrain conventions using Minitest and FactoryBot.

## Running Tests

### All Tests
```bash
bin/rails test
```

### Specific Test Files
```bash
# Run service tests
bin/rails test test/services/ai/open_router_client_test.rb
bin/rails test test/services/ai/app_generator_service_test.rb

# Run controller tests
bin/rails test test/controllers/account/app_editors_controller_test.rb

# Run job tests
bin/rails test test/jobs/app_generation_job_test.rb
bin/rails test test/jobs/process_app_update_job_test.rb

# Run system tests (requires headless Chrome)
bin/rails test:system
```

### With Coverage
```bash
COVERAGE=true bin/rails test
```

## Test Organization

### Unit Tests
- **Models**: `test/models/` - Model validations, associations, methods
- **Services**: `test/services/` - Business logic and external API integrations
- **Jobs**: `test/jobs/` - Background job processing

### Integration Tests
- **Controllers**: `test/controllers/` - Request/response cycles
- **System**: `test/system/` - Full browser-based user flows

## Factories

We use FactoryBot for test data. Key factories:

### Apps
```ruby
# Basic app
create(:app)

# App in different states
create(:app, :generating)
create(:app, :generated)
create(:app, :published)

# App with associations
create(:app, :with_files)
create(:app, :with_versions)
create(:app, :with_chat_messages)
```

### App Files
```ruby
# HTML file (default)
create(:app_file)

# Other file types
create(:app_file, :javascript)
create(:app_file, :css)
create(:app_file, :react)
```

### Chat Messages
```ruby
# User message
create(:app_chat_message, :user_message)

# Assistant response
create(:app_chat_message, :assistant_message)

# Different states
create(:app_chat_message, :processing)
create(:app_chat_message, :completed)
create(:app_chat_message, :failed)
```

## Mocking External Services

### OpenRouter API
```ruby
mock_client = Minitest::Mock.new
mock_client.expect(:chat, { success: true, content: "Response" }, [Array])

AI::OpenRouterClient.stub(:new, mock_client) do
  # Your test code
end
```

### Background Jobs
```ruby
# Test job enqueuing
assert_enqueued_with(job: AppGenerationJob) do
  AppGenerationJob.perform_later(generation)
end

# Test job execution
AppGenerationJob.perform_now(generation)
```

## Common Test Patterns

### Authentication
```ruby
setup do
  @user = create(:user)
  sign_in @user
end
```

### Turbo Streams
```ruby
post account_app_chat_messages_url(@app), params: {
  message: "Test message"
}, as: :turbo_stream

assert_response :success
```

### JSON APIs
```ruby
patch account_app_file_url(@app, @file), params: {
  content: "Updated content"
}, as: :json

json_response = JSON.parse(response.body)
assert json_response["success"]
```

## Troubleshooting

### Module Loading Issues
If you get `uninitialized constant AI::...` errors, the AI services may need explicit requires:
```ruby
require_relative "../../../app/services/ai/open_router_client"
```

### Database Cleaner
Tests use transactional fixtures by default. Each test runs in a transaction that's rolled back.

### System Tests
System tests require Chrome/Chromium. Install with:
```bash
# macOS
brew install --cask google-chrome

# Or use headless mode
HEADLESS=true bin/rails test:system
```

## Best Practices

1. **Use Factories**: Don't create test data manually
2. **Test Happy Path & Edge Cases**: Cover success and failure scenarios
3. **Mock External Services**: Don't make real API calls in tests
4. **Keep Tests Fast**: Use stubs/mocks instead of hitting the database when possible
5. **Test One Thing**: Each test should verify a single behavior
6. **Use Descriptive Names**: Test names should explain what they're testing

## CI/CD

Tests are automatically run on:
- Pull requests
- Pushes to main branch
- Before deployment

Ensure all tests pass before merging!