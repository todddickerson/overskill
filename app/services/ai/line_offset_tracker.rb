# Line Offset Tracker for Sequential Line Replacements
# Tracks line number changes when multiple replacements are made to the same file
# This solves the issue where subsequent replacements fail because line numbers have shifted

module Ai
  class LineOffsetTracker
    def initialize
      # Track cumulative offset per file
      # Key: file_path, Value: array of offset records
      @file_offsets = {}
      @logger = Rails.logger
    end

    # Record a line replacement and calculate the offset
    def record_replacement(file_path, original_first_line, original_last_line, new_line_count)
      @file_offsets[file_path] ||= []

      # Calculate the line difference
      original_line_count = original_last_line - original_first_line + 1
      line_difference = new_line_count - original_line_count

      # Apply existing offsets to get the actual line numbers used
      adjusted_first = adjust_line_number(file_path, original_first_line, skip_last: true)
      adjusted_last = adjust_line_number(file_path, original_last_line, skip_last: true)

      # Record this replacement
      offset_record = {
        original_first: original_first_line,
        original_last: original_last_line,
        adjusted_first: adjusted_first,
        adjusted_last: adjusted_last,
        line_difference: line_difference,
        timestamp: Time.current
      }

      @file_offsets[file_path] << offset_record

      @logger.info "[LineOffsetTracker] Recorded replacement for #{file_path}:"
      @logger.info "  Original lines: #{original_first_line}-#{original_last_line}"
      @logger.info "  Adjusted lines: #{adjusted_first}-#{adjusted_last}"
      @logger.info "  Line difference: #{(line_difference > 0) ? "+" : ""}#{line_difference}"

      offset_record
    end

    # Adjust a line number based on all previous replacements for THIS FILE ONLY
    def adjust_line_number(file_path, line_number, skip_last: false)
      # Return original if we're not tracking this specific file
      return line_number unless @file_offsets[file_path]

      adjusted = line_number
      offsets = skip_last ? @file_offsets[file_path][0...-1] : @file_offsets[file_path]

      # Sort offsets by original_first to ensure we process them in order
      sorted_offsets = offsets.sort_by { |o| o[:original_first] }

      sorted_offsets.each do |offset|
        # If the line is after a replacement, adjust it
        if line_number > offset[:original_last]
          adjusted += offset[:line_difference]
          @logger.debug "[LineOffsetTracker] Line #{line_number} is after replacement at #{offset[:original_first]}-#{offset[:original_last]}, adjusting by #{offset[:line_difference]}"
        elsif line_number.between?(offset[:original_first], offset[:original_last])
          # Line is within a replaced section - this might need special handling
          # For replacements within replaced sections, we need to be careful
          @logger.warn "[LineOffsetTracker] Line #{line_number} is within previously replaced section #{offset[:original_first]}-#{offset[:original_last]}"
          # Keep the line as the start of the replaced section
          adjusted = offset[:adjusted_first]
          break # Don't apply further adjustments
        end
      end

      if adjusted != line_number
        @logger.info "[LineOffsetTracker] File '#{file_path}': Adjusted line #{line_number} -> #{adjusted} (#{sorted_offsets.size} previous replacements)"
        @logger.debug "[LineOffsetTracker] Replacement history: #{sorted_offsets.map { |o| "L#{o[:original_first]}-#{o[:original_last]}(#{(o[:line_difference] > 0) ? "+" : ""}#{o[:line_difference]})" }.join(", ")}"
      end

      adjusted
    end

    # Adjust a range of line numbers
    def adjust_line_range(file_path, first_line, last_line)
      adjusted_first = adjust_line_number(file_path, first_line)
      adjusted_last = adjust_line_number(file_path, last_line)

      [adjusted_first, adjusted_last]
    end

    # Get the cumulative offset for a file at a specific line
    def get_cumulative_offset(file_path, line_number)
      return 0 unless @file_offsets[file_path]

      offset = 0
      @file_offsets[file_path].each do |record|
        if line_number > record[:original_last]
          offset += record[:line_difference]
        end
      end

      offset
    end

    # Clear offsets for a specific file
    def clear_file(file_path)
      @file_offsets.delete(file_path)
      @logger.info "[LineOffsetTracker] Cleared offsets for #{file_path}"
    end

    # Clear all offsets
    def clear_all
      @file_offsets.clear
      @logger.info "[LineOffsetTracker] Cleared all offset tracking"
    end

    # Get summary of offsets for a file
    def file_summary(file_path)
      return nil unless @file_offsets[file_path]

      {
        file_path: file_path,
        replacement_count: @file_offsets[file_path].size,
        total_line_change: @file_offsets[file_path].sum { |r| r[:line_difference] },
        replacements: @file_offsets[file_path]
      }
    end

    # Check if we're tracking a file
    def tracking?(file_path)
      @file_offsets.key?(file_path)
    end
  end
end
