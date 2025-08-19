# frozen_string_literal: true

# Termination evaluator for determining when to stop app generation
# Extracted from AppBuilderV5 to improve code organization
class Ai::TerminationEvaluator
  def should_terminate?(state, result)
    # Multiple termination conditions
    return true if all_goals_satisfied?(state)
    return true if stagnation_detected?(state)
    return true if error_threshold_exceeded?(state)
    return true if complexity_limit_reached?(state)
    
    false
  end
  
  private
  
  def all_goals_satisfied?(state)
    # Check if all goals are completed
    return false unless state[:goals].is_a?(Array) && state[:completed_goals].is_a?(Array)
    
    # All goals are satisfied when completed_goals contains all goals
    state[:goals].all? { |goal| state[:completed_goals].include?(goal) }
  end
  
  def stagnation_detected?(state)
    return false if state[:iteration] < 4
    
    # Check if making progress
    recent_history = state[:history].last(4)
    return false if recent_history.count < 4
    
    # Multiple stagnation indicators
    
    # 1. Same action type repeated and failing
    actions = recent_history.map { |h| h[:action][:type] }
    verifications = recent_history.map { |h| h[:verification][:success] }
    
    if actions.uniq.size == 1 && verifications.none?
      Rails.logger.warn "[V5_STAGNATION] Same action #{actions.first} failing repeatedly"
      return true
    end
    
    # 2. No goal progress in recent iterations (with nil safety)
    goal_progress_history = recent_history.map { |h| h&.dig(:goals_progress, :completed) }.compact
    if goal_progress_history.size > 1 && goal_progress_history.uniq.size == 1
      Rails.logger.warn "[V5_STAGNATION] No goal progress in last #{recent_history.count} iterations"
      return true
    end
    
    # 3. Verification confidence consistently low (with nil safety)
    confidence_scores = recent_history.map { |h| h&.dig(:verification, :confidence) || 0 }.compact
    avg_confidence = confidence_scores.any? ? confidence_scores.sum / confidence_scores.count.to_f : 0
    if avg_confidence < 0.3
      Rails.logger.warn "[V5_STAGNATION] Low confidence trend: #{avg_confidence.round(2)}"
      return true
    end
    
    false
  end
  
  def error_threshold_exceeded?(state)
    state[:errors].count > 10
  end
  
  def complexity_limit_reached?(state)
    state[:generated_files].count > 100
  end
end