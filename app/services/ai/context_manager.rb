# frozen_string_literal: true

# Context manager for tracking app generation context and implementation plans
# Extracted from AppBuilderV5 to improve code organization
class Ai::ContextManager
  def initialize(app)
    @app = app
    @context = {}
    @implementation_plan = nil
  end

  def add_context(data)
    @context.merge!(data)
  end

  def set_implementation_plan(plan)
    @implementation_plan = plan
  end

  def update_from_result(result)
    @context[:last_result] = result
    @context[:last_action] = result[:action]
  end

  def completeness_score
    # Calculate how complete our context is
    score = 0
    score += 25 if @context[:requirements]
    score += 25 if @implementation_plan
    score += 25 if @context[:last_result]
    score += 25 if @app.app_files.any?
    score
  end
end
