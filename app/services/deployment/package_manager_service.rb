module Deployment
  # Package management service for handling npm dependencies in generated apps
  # Similar to Lovable's lov-add-dependency and lov-remove-dependency tools
  class PackageManagerService
    PACKAGE_JSON_TEMPLATE = {
      name: "overskill-app",
      version: "0.1.0",
      type: "module",
      scripts: {
        dev: "vite",
        build: "vite build",
        preview: "vite preview",
        lint: "eslint . --ext js,jsx --report-unused-disable-directives --max-warnings 0"
      },
      dependencies: {
        react: "^18.2.0",
        "react-dom": "^18.2.0",
        "react-router-dom": "^6.20.0"
      },
      devDependencies: {
        "@types/react": "^18.2.43",
        "@types/react-dom": "^18.2.17",
        "@vitejs/plugin-react-swc": "^3.11.0",
        "@eslint/js": "^8.55.0",
        eslint: "^8.55.0",
        "eslint-plugin-react": "^7.33.2",
        "eslint-plugin-react-hooks": "^4.6.0",
        "eslint-plugin-react-refresh": "^0.4.5",
        vite: "^5.0.8"
      }
    }.freeze

    # Common packages and their appropriate versions for React/Vite apps
    PACKAGE_REGISTRY = {
      # UI Libraries
      "tailwindcss" => {version: "^3.4.0", dev: true},
      "autoprefixer" => {version: "^10.4.16", dev: true},
      "postcss" => {version: "^8.4.32", dev: true},
      "@headlessui/react" => {version: "^1.7.17", dev: false},
      "@heroicons/react" => {version: "^2.0.18", dev: false},
      "framer-motion" => {version: "^10.16.0", dev: false},

      # State Management
      "zustand" => {version: "^4.4.0", dev: false},
      "valtio" => {version: "^1.12.0", dev: false},
      "jotai" => {version: "^2.6.0", dev: false},

      # Forms & Validation
      "react-hook-form" => {version: "^7.48.0", dev: false},
      "zod" => {version: "^3.22.0", dev: false},
      "@hookform/resolvers" => {version: "^3.3.0", dev: false},

      # Data Fetching
      "@tanstack/react-query" => {version: "^5.17.0", dev: false},
      "axios" => {version: "^1.6.0", dev: false},
      "swr" => {version: "^2.2.0", dev: false},

      # Database & Backend
      "@supabase/supabase-js" => {version: "^2.39.0", dev: false},
      "firebase" => {version: "^10.7.0", dev: false},

      # Charts & Visualization
      "recharts" => {version: "^2.10.0", dev: false},
      "chart.js" => {version: "^4.4.0", dev: false},
      "react-chartjs-2" => {version: "^5.2.0", dev: false},
      "d3" => {version: "^7.8.0", dev: false},

      # Utils
      "lodash" => {version: "^4.17.21", dev: false},
      "date-fns" => {version: "^3.0.0", dev: false},
      "dayjs" => {version: "^1.11.10", dev: false},
      "uuid" => {version: "^9.0.1", dev: false},
      "clsx" => {version: "^2.1.0", dev: false},

      # Testing
      "vitest" => {version: "^1.1.0", dev: true},
      "@testing-library/react" => {version: "^14.1.0", dev: true},
      "@testing-library/jest-dom" => {version: "^6.1.0", dev: true},

      # TypeScript
      "typescript" => {version: "^5.3.0", dev: true},
      "@types/node" => {version: "^20.10.0", dev: true}
    }.freeze

    def initialize(app)
      @app = app
    end

    # Add a dependency to the project (similar to Lovable's lov-add-dependency)
    def add_dependency(package_name, version = nil, is_dev = false)
      package_json = get_or_create_package_json

      # Parse package specification (e.g., "lodash@latest" or "react@^18.0.0")
      if package_name.include?("@")
        parts = package_name.split("@")
        package_name = parts[0]
        version = parts[1] if parts[1].present?
      end

      # Use registry version if no version specified
      if version.nil? && PACKAGE_REGISTRY[package_name]
        registry_info = PACKAGE_REGISTRY[package_name]
        version = registry_info[:version]
        is_dev ||= registry_info[:dev]
      end

      version ||= "latest"

      # Add to appropriate dependency section
      dependency_key = is_dev ? :devDependencies : :dependencies
      package_json[dependency_key] ||= {}
      package_json[dependency_key][package_name] = version

      # Save updated package.json
      save_package_json(package_json)

      Rails.logger.info "[PackageManager] Added #{package_name}@#{version} to #{is_dev ? "devDependencies" : "dependencies"}"

      {
        success: true,
        package: package_name,
        version: version,
        is_dev: is_dev,
        message: "Added #{package_name}@#{version} to package.json"
      }
    rescue => e
      Rails.logger.error "[PackageManager] Failed to add dependency: #{e.message}"
      {
        success: false,
        error: e.message
      }
    end

    # Remove a dependency from the project (similar to Lovable's lov-remove-dependency)
    def remove_dependency(package_name)
      package_json = get_package_json
      return {success: false, error: "No package.json found"} unless package_json

      removed_from = nil

      # Check both dependencies and devDependencies
      if package_json[:dependencies]&.key?(package_name)
        package_json[:dependencies].delete(package_name)
        removed_from = "dependencies"
      end

      if package_json[:devDependencies]&.key?(package_name)
        package_json[:devDependencies].delete(package_name)
        removed_from = removed_from ? "both" : "devDependencies"
      end

      if removed_from
        save_package_json(package_json)

        Rails.logger.info "[PackageManager] Removed #{package_name} from #{removed_from}"

        {
          success: true,
          package: package_name,
          removed_from: removed_from,
          message: "Removed #{package_name} from package.json"
        }
      else
        {
          success: false,
          error: "Package #{package_name} not found in dependencies"
        }
      end
    rescue => e
      Rails.logger.error "[PackageManager] Failed to remove dependency: #{e.message}"
      {
        success: false,
        error: e.message
      }
    end

    # Update package.json with multiple dependencies at once
    def update_dependencies(dependencies_to_add = [], dependencies_to_remove = [])
      package_json = get_or_create_package_json

      added = []
      removed = []
      errors = []

      # Add dependencies
      dependencies_to_add.each do |dep|
        package_name = dep[:package] || dep["package"]
        version = dep[:version] || dep["version"]
        is_dev = dep[:is_dev] || dep["is_dev"] || false

        result = add_dependency_to_json(package_json, package_name, version, is_dev)
        if result[:success]
          added << package_name
        else
          errors << result[:error]
        end
      end

      # Remove dependencies
      dependencies_to_remove.each do |package_name|
        if remove_dependency_from_json(package_json, package_name)
          removed << package_name
        end
      end

      # Save if changes were made
      if added.any? || removed.any?
        save_package_json(package_json)
      end

      {
        success: errors.empty?,
        added: added,
        removed: removed,
        errors: errors
      }
    end

    # Get list of current dependencies
    def list_dependencies
      package_json = get_package_json
      return {success: false, error: "No package.json found"} unless package_json

      {
        success: true,
        dependencies: package_json[:dependencies] || {},
        devDependencies: package_json[:devDependencies] || {},
        scripts: package_json[:scripts] || {}
      }
    end

    # Check if a package is installed
    def has_dependency?(package_name)
      package_json = get_package_json
      return false unless package_json

      package_json[:dependencies]&.key?(package_name) ||
        package_json[:devDependencies]&.key?(package_name)
    end

    # Get recommended packages for a specific feature
    def get_recommendations(feature_type)
      case feature_type.to_s.downcase
      when "ui", "styling"
        {
          packages: ["tailwindcss", "@headlessui/react", "@heroicons/react", "framer-motion"],
          reason: "Modern UI and styling libraries for React"
        }
      when "forms"
        {
          packages: ["react-hook-form", "zod", "@hookform/resolvers"],
          reason: "Form handling with validation"
        }
      when "state"
        {
          packages: ["zustand"],
          reason: "Lightweight state management"
        }
      when "data", "api"
        {
          packages: ["@tanstack/react-query", "axios"],
          reason: "Data fetching and caching"
        }
      when "database", "backend"
        {
          packages: ["@supabase/supabase-js"],
          reason: "Backend and database integration"
        }
      when "charts", "visualization"
        {
          packages: ["recharts"],
          reason: "Data visualization components"
        }
      when "testing"
        {
          packages: ["vitest", "@testing-library/react"],
          reason: "Testing framework for React/Vite"
        }
      else
        {
          packages: [],
          reason: "No specific recommendations for '#{feature_type}'"
        }
      end
    end

    private

    def get_package_json
      file = @app.app_files.find_by(path: "package.json")
      return nil unless file

      begin
        JSON.parse(file.content, symbolize_names: true)
      rescue JSON::ParserError => e
        Rails.logger.error "[PackageManager] Failed to parse package.json: #{e.message}"
        nil
      end
    end

    def get_or_create_package_json
      package_json = get_package_json

      if package_json.nil?
        # Create default package.json
        package_json = PACKAGE_JSON_TEMPLATE.deep_dup
        package_json[:name] = "overskill-app-#{@app.id}"
        save_package_json(package_json)
      end

      package_json
    end

    def save_package_json(package_json)
      file = @app.app_files.find_or_initialize_by(path: "package.json")
      file.content = JSON.pretty_generate(package_json)
      file.file_type = "json"
      file.save!

      # Clear app cache since we modified a file
      Ai::ContextCacheService.new.clear_app_cache(@app.id)
    end

    def add_dependency_to_json(package_json, package_name, version, is_dev)
      return {success: false, error: "Package name required"} unless package_name.present?

      # Parse package specification
      if package_name.include?("@") && !package_name.start_with?("@")
        parts = package_name.split("@")
        package_name = parts[0]
        version = parts[1] if parts[1].present?
      end

      # Use registry version if available
      if version.nil? && PACKAGE_REGISTRY[package_name]
        registry_info = PACKAGE_REGISTRY[package_name]
        version = registry_info[:version]
        is_dev ||= registry_info[:dev]
      end

      version ||= "latest"

      dependency_key = is_dev ? :devDependencies : :dependencies
      package_json[dependency_key] ||= {}
      package_json[dependency_key][package_name] = version

      {success: true}
    rescue => e
      {success: false, error: e.message}
    end

    def remove_dependency_from_json(package_json, package_name)
      removed = false

      if package_json[:dependencies]&.key?(package_name)
        package_json[:dependencies].delete(package_name)
        removed = true
      end

      if package_json[:devDependencies]&.key?(package_name)
        package_json[:devDependencies].delete(package_name)
        removed = true
      end

      removed
    end
  end
end
