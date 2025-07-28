# Contributing to OverSkill

Thank you for your interest in contributing to OverSkill! We're building the future of AI-powered app creation and welcome contributions from the community.

## Code of Conduct

We follow the [Contributor Covenant Code of Conduct](https://www.contributor-covenant.org/). Please read and follow it in all interactions with the project.

## How to Contribute

### Reporting Bugs

1. Check if the bug has already been reported in [Issues](https://github.com/yourusername/overskill/issues)
2. Create a new issue with:
   - Clear title and description
   - Steps to reproduce
   - Expected vs actual behavior
   - Screenshots if applicable
   - Environment details (OS, Ruby version, etc.)

### Suggesting Features

1. Check existing [Issues](https://github.com/yourusername/overskill/issues) and [Discussions](https://github.com/yourusername/overskill/discussions)
2. Create a new discussion with:
   - Problem you're trying to solve
   - Proposed solution
   - Alternative solutions considered
   - Mockups/examples if applicable

### Code Contributions

#### Setup Development Environment

```bash
# Fork and clone the repository
git clone git@github.com:yourusername/overskill.git
cd overskill

# Install dependencies
bin/setup

# Create a branch for your feature
git checkout -b feature/your-feature-name

# Make your changes and run tests
bin/rails test

# Run linting
bundle exec standardrb

# Start the development server
bin/dev
```

#### Development Guidelines

1. **Follow BulletTrain Conventions**
   - Use super scaffolding for new models
   - Follow the account-scoped pattern
   - Use BulletTrain's components

2. **Write Tests**
   - Add tests for new features
   - Ensure existing tests pass
   - Aim for >80% coverage

3. **Code Style**
   - Follow Ruby Style Guide (enforced by Standard)
   - Use meaningful variable/method names
   - Add comments for complex logic
   - Keep methods small and focused

4. **Commit Messages**
   ```
   feat: Add AI prompt enhancement
   
   - Add PromptEnhancer service
   - Include app type detection
   - Add tests for enhancement logic
   
   Closes #123
   ```

   Types: feat, fix, docs, style, refactor, test, chore

#### Pull Request Process

1. **Before Submitting**
   - Rebase on latest main branch
   - Run full test suite
   - Update documentation if needed
   - Add yourself to CONTRIBUTORS.md

2. **PR Description Template**
   ```markdown
   ## Description
   Brief description of changes
   
   ## Type of Change
   - [ ] Bug fix
   - [ ] New feature
   - [ ] Breaking change
   - [ ] Documentation update
   
   ## Testing
   - [ ] Unit tests pass
   - [ ] Integration tests pass
   - [ ] Manual testing completed
   
   ## Checklist
   - [ ] Code follows style guidelines
   - [ ] Self-review completed
   - [ ] Comments added for complex code
   - [ ] Documentation updated
   - [ ] No new warnings
   ```

3. **Review Process**
   - PRs require one approval
   - Address review feedback
   - Keep PRs focused and small
   - Squash commits before merge

### Documentation

- Update README.md for user-facing changes
- Update technical docs in /docs
- Add inline code comments
- Include examples for new features

### Testing

#### Running Tests

```bash
# Run all tests
bin/rails test

# Run specific test file
bin/rails test test/models/app_test.rb

# Run specific test
bin/rails test test/models/app_test.rb:42

# Run system tests
bin/rails test:system

# Run with coverage
COVERAGE=true bin/rails test
```

#### Writing Tests

```ruby
# Example test structure
class AppGeneratorServiceTest < ActiveSupport::TestCase
  setup do
    @user = create(:user)
    @service = AI::AppGeneratorService.new(@user)
  end
  
  test "generates app from valid prompt" do
    VCR.use_cassette("ai_generation") do
      result = @service.generate("Create a todo app")
      
      assert result[:success]
      assert_equal "todo-app", result[:app].slug
      assert result[:files].any?
    end
  end
  
  test "handles invalid prompt gracefully" do
    result = @service.generate("")
    
    assert_not result[:success]
    assert_includes result[:error], "Prompt cannot be blank"
  end
end
```

### Security

- Never commit secrets or API keys
- Report security issues privately to security@overskill.app
- Follow secure coding practices
- Validate and sanitize all inputs

### Performance

- Profile before optimizing
- Add database indexes for new queries
- Use background jobs for slow operations
- Cache expensive computations

## Project Structure

```
app/
├── controllers/     # Request handling
├── models/          # Business logic
├── services/        # Complex operations
├── jobs/           # Background tasks
├── views/          # UI templates
└── assets/         # CSS/JS

test/
├── models/         # Model tests
├── controllers/    # Controller tests
├── services/       # Service tests
├── system/         # End-to-end tests
└── fixtures/       # Test data
```

## Getting Help

- Join our [Discord](https://discord.gg/overskill)
- Check the [docs](https://docs.overskill.app)
- Ask in GitHub Discussions
- Email: dev@overskill.app

## Recognition

Contributors are recognized in:
- CONTRIBUTORS.md file
- Release notes
- Project website
- Annual contributor spotlight

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

---

Thank you for helping make OverSkill better! 🚀
