require 'test_helper'

module Ai
  class LineOffsetTrackerTest < ActiveSupport::TestCase
    setup do
      @tracker = LineOffsetTracker.new
    end
    
    test "tracks offset for single file with single replacement that adds lines" do
      file_path = "src/index.css"
      
      # First replacement: lines 10-20 replaced with 25 lines (adds 15 lines)
      @tracker.record_replacement(file_path, 10, 20, 25)
      
      # Lines before the replacement should not be adjusted
      assert_equal 5, @tracker.adjust_line_number(file_path, 5)
      
      # Lines after the replacement should be adjusted
      assert_equal 35, @tracker.adjust_line_number(file_path, 21) # 21 + 14 = 35
      assert_equal 45, @tracker.adjust_line_number(file_path, 31) # 31 + 14 = 45
    end
    
    test "tracks offset for single file with single replacement that removes lines" do
      file_path = "src/app.js"
      
      # First replacement: lines 50-70 replaced with 10 lines (removes 11 lines)
      @tracker.record_replacement(file_path, 50, 70, 10)
      
      # Lines before the replacement should not be adjusted
      assert_equal 45, @tracker.adjust_line_number(file_path, 45)
      
      # Lines after the replacement should be adjusted (shifted up)
      assert_equal 60, @tracker.adjust_line_number(file_path, 71) # 71 - 11 = 60
      assert_equal 89, @tracker.adjust_line_number(file_path, 100) # 100 - 11 = 89
    end
    
    test "tracks multiple replacements on same file cumulatively" do
      file_path = "src/index.css"
      
      # First replacement: lines 9-39 replaced with 45 lines (adds 14 lines)
      @tracker.record_replacement(file_path, 9, 39, 45)
      
      # Second replacement: lines 51-78 replaced with 34 lines (adds 6 lines)
      # Note: These are the ORIGINAL line numbers from Claude's perspective
      # They should be adjusted to 65-92 after the first replacement
      adjusted_first, adjusted_last = @tracker.adjust_line_range(file_path, 51, 78)
      assert_equal 65, adjusted_first # 51 + 14
      assert_equal 92, adjusted_last  # 78 + 14
      
      @tracker.record_replacement(file_path, 51, 78, 34)
      
      # Lines after both replacements should have cumulative adjustment
      assert_equal 120, @tracker.adjust_line_number(file_path, 100) # 100 + 14 + 6 = 120
    end
    
    test "tracks offsets separately for different files" do
      file1 = "src/index.css"
      file2 = "src/app.js"
      
      # Replacement in file1: lines 20-30 (11 lines) replaced with 20 lines (adds 9 lines)
      @tracker.record_replacement(file1, 20, 30, 20)
      
      # Replacement in file2: lines 15-25 (11 lines) replaced with 5 lines (removes 6 lines)
      @tracker.record_replacement(file2, 15, 25, 5)
      
      # file1 adjustments
      assert_equal 49, @tracker.adjust_line_number(file1, 40) # 40 + 9
      
      # file2 adjustments (completely independent of file1)
      assert_equal 34, @tracker.adjust_line_number(file2, 40) # 40 - 6
      
      # file3 (not tracked) should not be adjusted
      assert_equal 100, @tracker.adjust_line_number("src/other.js", 100)
    end
    
    test "handles CSS use case from the failed generation" do
      file_path = "src/index.css"
      
      # Simulate the exact scenario from the failed generation
      # First replacement: lines 9-39 (31 lines) replaced with 45 lines
      @tracker.record_replacement(file_path, 9, 39, 45)
      
      # Check line offset after first replacement
      offset = @tracker.get_cumulative_offset(file_path, 51)
      assert_equal 14, offset # 45 - 31 = 14 lines added
      
      # Second replacement should have adjusted line numbers
      # Original: 51-78, Adjusted: 65-92
      adjusted_first, adjusted_last = @tracker.adjust_line_range(file_path, 51, 78)
      assert_equal 65, adjusted_first
      assert_equal 92, adjusted_last
      
      # Third replacement should also be adjusted
      # Original: 100-119, should be adjusted by 14 (from first replacement)
      adjusted_first, adjusted_last = @tracker.adjust_line_range(file_path, 100, 119)
      assert_equal 114, adjusted_first # 100 + 14
      assert_equal 133, adjusted_last  # 119 + 14
    end
    
    test "clear_file removes tracking for specific file" do
      file1 = "src/index.css"
      file2 = "src/app.js"
      
      @tracker.record_replacement(file1, 10, 20, 30)
      @tracker.record_replacement(file2, 5, 10, 15)
      
      assert @tracker.tracking?(file1)
      assert @tracker.tracking?(file2)
      
      @tracker.clear_file(file1)
      
      assert_not @tracker.tracking?(file1)
      assert @tracker.tracking?(file2)
      
      # file1 should no longer have adjustments
      assert_equal 50, @tracker.adjust_line_number(file1, 50)
      # file2 should still have adjustments
      assert_not_equal 50, @tracker.adjust_line_number(file2, 50)
    end
    
    test "file_summary provides correct information" do
      file_path = "src/index.css"
      
      # First: lines 10-20 (11 lines) replaced with 30 lines (adds 19 lines)
      @tracker.record_replacement(file_path, 10, 20, 30)
      
      # Second: lines 50-60 (11 lines) replaced with 55 lines (adds 44 lines)  
      @tracker.record_replacement(file_path, 50, 60, 55)
      
      summary = @tracker.file_summary(file_path)
      
      assert_equal file_path, summary[:file_path]
      assert_equal 2, summary[:replacement_count]
      assert_equal 63, summary[:total_line_change] # +19 +44 = +63
      assert_equal 2, summary[:replacements].size
    end
  end
end