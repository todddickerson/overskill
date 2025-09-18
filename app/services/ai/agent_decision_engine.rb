# frozen_string_literal: true

# Agent decision engine for determining next actions in app generation
# Extracted from AppBuilderV5 to improve code organization
class Ai::AgentDecisionEngine
  def determine_next_action(state)
    # Improved decision logic that considers goals progress
    if state[:iteration] == 1
      {type: :plan_implementation, description: "Create initial plan"}
    elsif state[:errors].any?
      {
        type: :debug_issues,
        description: "Fix errors",
        issues: state[:errors]
      }
    elsif !has_app_specific_features?(state)
      # Check if we need to implement the actual app features
      {
        type: :execute_tools,
        description: "Implement app-specific features",
        tools: determine_feature_tools(state)
      }
    elsif needs_verification?(state)
      {type: :verify_changes, description: "Verify generated code"}
    elsif all_goals_near_complete?(state)
      {type: :complete_task, description: "Finalize generation"}
    else
      {
        type: :execute_tools,
        description: "Continue implementation",
        tools: determine_next_tools(state)
      }
    end
  end

  def has_app_specific_features?(state)
    # Check if app-specific features have been implemented
    # Look for signs that the todo app functionality exists
    return false unless state[:files_generated] > 0

    # Check if we have key todo app files
    files = state[:generated_files] || []
    file_paths = files.map { |f| f.respond_to?(:path) ? f.path : f.to_s }

    # Look for key indicators that todo features are implemented
    has_todo_component = file_paths.any? { |p| p.include?("Todo") || p.include?("todo") }
    file_paths.any? { |p| p.include?("Task") || p.include?("task") }

    # Need both todo-related files AND sufficient implementation
    has_todo_component && state[:iteration] >= 3
  end

  def determine_feature_tools(state)
    # Tools for implementing app-specific features
    [
      {type: :implement_features, description: "Implement app-specific functionality"}
    ]
  end

  def determine_initial_tools(state)
    [
      {type: :generate_file, file_path: "package.json", description: "Create package.json"},
      {type: :generate_file, file_path: "src/App.tsx", description: "Create main App component"},
      {type: :generate_file, file_path: "src/main.tsx", description: "Create entry point"}
    ]
  end

  def determine_next_tools(state)
    # Determine what tools to run next based on state
    []
  end

  def needs_verification?(state)
    state[:iteration] > 1 && state[:iteration] % 3 == 0
  end

  def all_goals_near_complete?(state)
    state[:goals].count <= 1
  end
end
