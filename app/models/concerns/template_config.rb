# frozen_string_literal: true

# Central configuration for app templates
# This module defines which template is currently used for new apps
module TemplateConfig
  extend ActiveSupport::Concern

  # The current template version used for new apps
  # When updating to a new template, change this path
  CURRENT_TEMPLATE_PATH = Rails.root.join("app/services/ai/templates/overskill_20250728")

  # Template version identifier (for tracking/logging)
  CURRENT_TEMPLATE_VERSION = "overskill_20250728"

  included do
    # Make these available as instance methods too
    def current_template_path
      CURRENT_TEMPLATE_PATH
    end

    def current_template_version
      CURRENT_TEMPLATE_VERSION
    end
  end

  class_methods do
    def current_template_path
      CURRENT_TEMPLATE_PATH
    end

    def current_template_version
      CURRENT_TEMPLATE_VERSION
    end
  end
end
