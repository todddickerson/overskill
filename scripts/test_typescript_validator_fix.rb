#!/usr/bin/env ruby
# Test the TypeScript validator fix for escaped quotes in ternary operators

require_relative '../config/environment'

puts "🧪 Testing TypeScript Validator Quote Fix"
puts "=" * 60
puts

# Test cases with various quote issues
test_cases = [
  {
    name: "Ternary with escaped quotes (original bug)",
    input: 'toast.success(task.completed ? "Task marked as incomplete\" : \"Task completed! 🎉");',
    expected: 'toast.success(task.completed ? "Task marked as incomplete" : "Task completed! 🎉");',
    file_path: "test.tsx"
  },
  {
    name: "JSX className with escaped quote",
    input: '<div className="container\\">',
    expected: '<div className="container">',
    file_path: "test.tsx"
  },
  {
    name: "Nested ternary with quotes",
    input: 'const msg = isActive ? "Status is active\" : \"Status is inactive\";',
    expected: 'const msg = isActive ? "Status is active" : "Status is inactive";',
    file_path: "test.ts"
  },
  {
    name: "Valid escaped quotes (should not change)",
    input: 'const message = "He said \\"hello\\" to me";',
    expected: 'const message = "He said \\"hello\\" to me";',
    file_path: "test.ts"
  },
  {
    name: "Multiple ternary operators",
    input: 'const status = a ? "First\" : b ? \"Second\" : \"Third\";',
    expected: 'const status = a ? "First" : b ? "Second" : "Third";',
    file_path: "test.ts"
  },
  {
    name: "Function with ternary in parameter",
    input: 'setMessage(isError ? "Error occurred\" : \"Success!\");',
    expected: 'setMessage(isError ? "Error occurred" : "Success!");',
    file_path: "test.tsx"
  },
  {
    name: "JSX attribute with escaped quotes",
    input: '<Button variant=\\"default\\">Click</Button>',
    expected: '<Button variant="default">Click</Button>',
    file_path: "test.tsx"
  },
  {
    name: "Complex line with multiple issues",
    input: '<div className="test\\"><span>{show ? "Yes\" : \"No\"}</span></div>',
    expected: '<div className="test"><span>{show ? "Yes" : "No"}</span></div>',
    file_path: "test.tsx"
  }
]

# Create a dummy app for testing
app = App.last || App.create!(
  user: User.first,
  name: "TypeScript Validator Test",
  status: "generating"
)

validator = Ai::TypescriptValidatorService.new(app)
passed = 0
failed = 0

puts "Running #{test_cases.length} test cases..."
puts

test_cases.each_with_index do |test, index|
  print "Test #{index + 1}: #{test[:name]}... "
  
  # Test the validator
  result = validator.validate_and_fix_typescript(test[:file_path], test[:input])
  
  if result == test[:expected]
    puts "✅ PASSED"
    passed += 1
  else
    puts "❌ FAILED"
    failed += 1
    puts "  Input:    '#{test[:input]}'"
    puts "  Expected: '#{test[:expected]}'"
    puts "  Got:      '#{result}'"
    puts
  end
end

puts
puts "=" * 60
puts "📊 Test Results:"
puts "  Passed: #{passed}/#{test_cases.length}"
puts "  Failed: #{failed}/#{test_cases.length}"
puts

if failed == 0
  puts "✅ All tests passed! The TypeScript validator fix is working correctly."
else
  puts "❌ Some tests failed. The validator needs further adjustment."
end

# Test with the actual problematic code from the app
puts
puts "=" * 60
puts "🔍 Testing with actual app code..."
puts

actual_code = <<-CODE
  const toggleTask = (id: string) => {
    setTasks(prev => prev.map(task => 
      task.id === id 
        ? { ...task, completed: !task.completed }
        : task
    ));
    
    const task = tasks.find(t => t.id === id);
    if (task) {
      toast.success(task.completed ? "Task marked as incomplete\\" : \\"Task completed! 🎉");
    }
  };
CODE

fixed_code = validator.validate_and_fix_typescript("Index.tsx", actual_code)

if fixed_code.include?('? "Task marked as incomplete" : "Task completed! 🎉"')
  puts "✅ Successfully fixed the actual app code!"
else
  puts "❌ Failed to fix the actual app code"
  puts "Result:"
  puts fixed_code
end