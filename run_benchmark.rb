#!/usr/bin/env ruby
# Run the app quality benchmark system
require_relative 'config/environment'

puts "\n🚀 OverSkill App Generation Benchmark"
puts "="*60
puts "Testing our single optimized tech stack:"
puts "  • React + TypeScript"
puts "  • Cloudflare Workers"
puts "  • Supabase (Database + Auth)"
puts "  • Stripe Connect"
puts "="*60

# Initialize benchmark
benchmark = Ai::AppQualityBenchmark.new

# Run tests
if ARGV.include?('--quick')
  puts "\n⚡ Running quick benchmark (1 iteration)..."
  benchmark.run_full_benchmark(iterations: 1)
elsif ARGV.include?('--full')
  puts "\n📊 Running full benchmark (5 iterations)..."
  benchmark.run_full_benchmark(iterations: 5)
else
  puts "\n📝 Running standard benchmark (3 iterations)..."
  benchmark.run_full_benchmark(iterations: 3)
end

puts "\n✅ Benchmark complete!"
puts "\nUsage:"
puts "  ruby run_benchmark.rb           # Standard (3 iterations)"
puts "  ruby run_benchmark.rb --quick   # Quick test (1 iteration)"
puts "  ruby run_benchmark.rb --full    # Full test (5 iterations)"