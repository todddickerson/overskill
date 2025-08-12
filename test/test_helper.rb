# Simplecov config has to come before literally everything else
# Open coverage/index.html in your browser after
# running your tests for test coverage results.
require "simplecov"
SimpleCov.command_name "test" + (ENV["TEST_ENV_NUMBER"] || "")
SimpleCov.start "rails" do
  # By default we don't include avo in coverage reports since it's not user-facing application code.
  # If you want to get test coverage for your avo resources, you can comment out or remove the next line.
  add_filter "/avo/"
end

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"

# Ensure Rails.application has an executor (guard for certain Rails/test setups)
ensure_executor = proc do
  app = Rails.application
  unless app.respond_to?(:executor)
    # Define singleton methods to avoid being overwritten
    app.define_singleton_method(:executor) do
      @__bt_executor ||= Class.new do
        def perform
          yield
        end
      end.new
    end
    app.define_singleton_method(:executor=) do |val|
      @__bt_executor = val
    end
  end
end

# Global fallback: ensure every Rails::Application has an executor with `perform`
begin
  class Rails::Application
    def executor
      @__bt_executor ||= Class.new do
        def perform
          yield
        end
      end.new
    end
  end
rescue => e
  warn "[test_helper] Could not define Rails::Application#executor: #{e.message}"
end

ensure_executor.call

require "rails/test_help"

# Override ActiveSupport::Executor::TestHelper to be resilient in our environment
begin
  class ActiveSupport::Executor
    module TestHelper
      def run(*args, &block)
        # Bypass executor usage to avoid missing executor errors in our env
        super
      end
    end
  end
rescue => e
  warn "[test_helper] Could not override ActiveSupport::Executor::TestHelper: #{e.message}"
end

# Re-ensure after rails/test_help in case it modified Rails.application
ensure_executor.call
require "webmock/minitest"
require "mocha/minitest"

# Configure ActiveJob to use test adapter for testing
ActiveJob::Base.queue_adapter = :test

# Set the default language we test in to English.
I18n.default_locale = :en

# Skip global seeds in test to avoid collisions and speed up runs.
# If a test needs seed data, load it explicitly within that test or use factories.
# require File.expand_path("../../db/seeds", __FILE__)

# Ensure AI services are loaded for tests
Dir[Rails.root.join("app/services/ai/**/*.rb")].each { |f| require f }

if ENV["KNAPSACK_PRO_CI_NODE_INDEX"].present?
  require "knapsack_pro"
  knapsack_pro_adapter = KnapsackPro::Adapters::MinitestAdapter.bind
  knapsack_pro_adapter.set_test_helper_path(__FILE__)
else
  require "colorize"
  puts "Not requiring Knapsack Pro.".yellow
  puts "If you'd like to use Knapsack Pro make sure that you've set the environment variable KNAPSACK_PRO_CI_NODE_INDEX".yellow
end

require "sidekiq/testing"
Sidekiq::Testing.inline!

ENV["MINITEST_REPORTERS_REPORTS_DIR"] = "test/reports#{ENV["TEST_ENV_NUMBER"] || ""}"
require "minitest/reporters"

reporters = []

if ENV["BT_TEST_FORMAT"]&.downcase == "dots"
  # The classic "dot style" output:
  # ...S..E...F...
  reporters.push Minitest::Reporters::DefaultReporter.new
else
  # "Spec style" output that shows you which tests are executing as they run:
  # UserTest
  #   test_details_provided_should_be_true_when_details_are_provided  PASS (0.18s)
  reporters.push Minitest::Reporters::SpecReporter.new(print_failure_summary: true)
end

# This reporter generates XML documents into test/reports that are used by CI services to tally results.
# We add it last because doing so make the visible test output a little cleaner.
reporters.push Minitest::Reporters::JUnitReporter.new if ENV["CI"]

Minitest::Reporters.use! reporters

require "parallel_tests/test/runtime_logger" if ENV["PARALLEL_TESTS_RECORD_RUNTIME"]

begin
  require "bullet_train/billing/test_support"
  FactoryBot.definition_file_paths << BulletTrain::Billing::TestSupport::FACTORY_PATH
  FactoryBot.reload
rescue LoadError
end

begin
  require "bullet_train/billing/stripe/test_support"
  FactoryBot.definition_file_paths << BulletTrain::Billing::Stripe::TestSupport::FACTORY_PATH
  FactoryBot.reload
rescue LoadError
end

ActiveSupport::TestCase.class_eval do
  # Run tests in parallel with specified workers
  # parallelize(workers: :number_of_processors)

  fixtures :all

  # Add more helper methods to be used by all tests here...
end

class ActiveSupport::TestCase
  include FactoryBot::Syntax::Methods
  
  # WebMock configuration
  WebMock.disable_net_connect!(allow_localhost: true)
  
  # Common WebMock stubs for testing
  setup do
    # Stub pwned password API that's called during user creation
    stub_request(:get, /api\.pwnedpasswords\.com/)
      .to_return(status: 200, body: "", headers: {})
      
    # Stub any Claude/OpenAI API calls to avoid external dependencies in tests
    stub_request(:post, /api\.anthropic\.com/)
      .to_return(status: 200, body: '{"content": [{"text": "test response"}]}', headers: {'Content-Type' => 'application/json'})
      
    stub_request(:post, /api\.openai\.com/)
      .to_return(status: 200, body: '{"choices": [{"message": {"content": "test response"}}]}', headers: {'Content-Type' => 'application/json'})
      
    # Stub Cloudflare API calls to avoid external dependencies in tests
    stub_request(:put, /api\.cloudflare\.com/)
      .to_return(status: 200, body: '{"success": true, "result": {"id": "test-worker"}}', headers: {'Content-Type' => 'application/json'})
      
    stub_request(:post, /api\.cloudflare\.com/)
      .to_return(status: 200, body: '{"success": true, "result": {"id": "test-worker"}}', headers: {'Content-Type' => 'application/json'})
  end
end
