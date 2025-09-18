require "test_helper"

module Ai
  class LineReplaceServiceTest < ActiveSupport::TestCase
    setup do
      # Create test data
      @user = User.find_or_create_by!(email: "test@example.com") do |u|
        u.password = "password123"
        u.first_name = "Test"
        u.last_name = "User"
      end
      @team = Team.create!(
        name: "Test Team #{SecureRandom.hex(4)}"
      )
      @membership = Membership.create!(
        user: @user,
        team: @team,
        user_first_name: @user.first_name,
        user_last_name: @user.last_name,
        user_email: @user.email
      )
    end

    teardown do
      # Clean up all apps created during tests
      @team&.apps&.destroy_all
    end

    test "detects and prevents properties outside export block in config files" do
      # This test reproduces the exact issue that happened with tailwind.config.ts
      # where the AI closed the config object too early, leaving plugins outside

      app = App.create!(
        team: @team,
        name: "Test App 1",
        status: "ready",
        creator: @membership,
        prompt: "Test prompt"
      )

      # Create a tailwind config file
      file = app.app_files.create!(
        team: @team,
        path: "tailwind.config.ts",
        content: <<~TS
          import type { Config } from "tailwindcss";

          export default {
            content: ["./src/**/*.{js,jsx,ts,tsx}"],
            theme: {
              extend: {
                boxShadow: {
                  '3xl': '0 35px 60px -15px rgba(0, 0, 0, 0.3)',
                  '4xl': '0 45px 80px -20px rgba(0, 0, 0, 0.35)',
                  '5xl': '0 55px 100px -25px rgba(0, 0, 0, 0.4)'
                }
              }
            },
            plugins: [require("tailwindcss-animate")],
          } satisfies Config;
        TS
      )

      # Simulate what the AI tried to do - close the config object early
      # The AI's Line-replace tried to change lines 11-12 (the closing of theme and config)
      search_pattern = <<~SEARCH
          }
        },
      SEARCH

      # The malformed replacement that puts plugins outside
      malformed_replacement = <<~REPLACE
            }
          }
        },
        plugins: [require("tailwindcss-animate")],
      REPLACE

      # This should FAIL validation due to structural issues
      service = LineReplaceService.new(file, search_pattern, 11, 12, malformed_replacement)
      result = service.execute

      assert_not result[:success], "Should reject malformed config structure"
      assert_includes result[:error], "structural issues", "Should mention structural issues"

      # Verify the file wasn't changed
      file.reload
      assert_includes file.content, "plugins: [require", "Original file should still have plugins inside"
      assert_not_includes file.content, "},\n          plugins:", "Should not have malformed structure"
    end

    test "accepts valid config file replacements" do
      app = App.create!(
        team: @team,
        name: "Test App 2",
        status: "ready",
        creator: @membership,
        prompt: "Test prompt"
      )

      # Create a config file
      file = app.app_files.create!(
        team: @team,
        path: "vite.config.js",
        content: <<~JS
          export default {
            server: {
              port: 3000
            }
          }
        JS
      )

      # Valid replacement that maintains structure
      search_pattern = <<~SEARCH
        server: {
          port: 3000
        }
      SEARCH

      valid_replacement = <<~REPLACE
        server: {
          port: 8080,
          host: "0.0.0.0"
        }
      REPLACE

      service = LineReplaceService.new(file, search_pattern, 2, 4, valid_replacement)
      result = service.execute

      assert result[:success], "Should accept valid config changes"

      file.reload
      assert_includes file.content, "port: 8080", "Should update port"
      assert_includes file.content, 'host: "0.0.0.0"', "Should add host"

      # Verify structure is still valid
      assert_equal file.content.count("{"), file.content.count("}"), "Braces should be balanced"
    end

    test "detects unmatched braces in javascript files" do
      app = App.create!(
        team: @team,
        name: "Test App 3",
        status: "ready",
        creator: @membership,
        prompt: "Test prompt"
      )

      file = app.app_files.create!(
        team: @team,
        path: "app.js",
        content: <<~JS
          function test() {
            console.log('hello');
          }
        JS
      )

      # Replacement that creates unmatched braces
      search_pattern = "  console.log('hello');"
      bad_replacement = <<~REPLACE
        console.log('hello');
        if (true) {
          console.log('world');
        // Missing closing brace!
      REPLACE

      service = LineReplaceService.new(file, search_pattern, 2, 2, bad_replacement)
      result = service.execute

      assert_not result[:success], "Should reject unmatched braces"
      assert_includes result[:error].downcase, "unmatched", "Should mention unmatched braces"
    end

    test "validates TypeScript config files correctly" do
      app = App.create!(
        team: @team,
        name: "Test App 4",
        status: "ready",
        creator: @membership,
        prompt: "Test prompt"
      )

      file = app.app_files.create!(
        team: @team,
        path: "tsconfig.json",
        file_type: "json",
        content: <<~JSON
          {
            "compilerOptions": {
              "target": "es5",
              "module": "commonjs"
            }
          }
        JSON
      )

      # Try to break the JSON structure
      search_pattern = <<~SEARCH
        "compilerOptions": {
          "target": "es5",
          "module": "commonjs"
        }
      SEARCH

      # This would create invalid JSON with properties outside
      bad_replacement = <<~REPLACE
          "compilerOptions": {
            "target": "es2020",
            "module": "esnext"
          }
        },
        "include": ["src/**/*"]
      REPLACE

      service = LineReplaceService.new(file, search_pattern, 2, 5, bad_replacement)
      result = service.execute

      # This should fail because it would create unbalanced braces in JSON
      assert_not result[:success], "Should reject malformed JSON structure"
    end

    test "prevents tailwind plugins outside config object" do
      # Specific test for the exact Tailwind issue we encountered
      app = App.create!(
        team: @team,
        name: "Test App 5",
        status: "ready",
        creator: @membership,
        prompt: "Test prompt"
      )

      file = app.app_files.create!(
        team: @team,
        path: "tailwind.config.ts",
        content: <<~TS
          export default {
            content: ["./src/**/*.{tsx,ts,jsx,js}"],
            theme: {
              extend: {
                colors: {
                  primary: "#000"
                }
              }
            }
          }
        TS
      )

      # AI tries to add plugins but closes the object first
      search_pattern = <<~SEARCH
            }
          }
        }
      SEARCH

      # This is what the AI wrongly generated
      wrong_replacement = <<~REPLACE
            }
          }
        },
        plugins: [require("tailwindcss-animate")]
        }
      REPLACE

      service = LineReplaceService.new(file, search_pattern, 7, 9, wrong_replacement)
      result = service.execute

      assert_not result[:success], "Should detect plugins outside config"
      assert_match(/plugins.*outside|structural/i, result[:error], "Should mention structural issue with plugins")
    end
  end
end
