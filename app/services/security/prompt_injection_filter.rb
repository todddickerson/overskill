# frozen_string_literal: true

module Security
  class PromptInjectionFilter
    # Dangerous patterns that indicate potential prompt injection attempts
    INJECTION_PATTERNS = [
      # Direct instruction override attempts
      /ignore\s+(all\s+)?previous\s+(instructions?|commands?|rules?)/i,
      /forget\s+(everything|all|previous|prior)\s*(instructions?|commands?)?/i,
      /disregard\s+(all\s+)?(previous|prior|above)\s*(instructions?|rules?)?/i,
      /override\s+(system|admin|security)\s*(settings?|rules?|instructions?)?/i,
      
      # Role/mode switching attempts
      /you\s+are\s+now\s+(in\s+)?(developer|admin|root|debug|test)\s*mode/i,
      /switch\s+to\s+(developer|admin|root|debug|test)\s*mode/i,
      /enter\s+(developer|admin|root|debug|test)\s*mode/i,
      /activate\s+(developer|admin|root|debug|test)\s*mode/i,
      
      # System prompt extraction attempts
      /reveal\s+(your\s+)?(system\s+)?prompts?/i,
      /show\s+(me\s+)?(your\s+)?(system\s+)?prompts?/i,
      /display\s+(your\s+)?(original|initial|system)\s+instructions?/i,
      /what\s+(are\s+)?your\s+(original|initial|system)\s+instructions?/i,
      /repeat\s+(your\s+)?(system\s+)?instructions?/i,
      /print\s+(your\s+)?(system\s+)?prompts?/i,
      
      # Special character injection patterns
      /\#\#\#\s*(system|admin|root|override)/i,
      /\[\[SYSTEM\]\]/i,
      /<<<\s*OVERRIDE\s*>>>/i,
      /\{\{\s*ADMIN\s*\}\}/i,
      
      # Code/command injection attempts
      /execute\s+(system\s+)?commands?:/i,
      /run\s+(the\s+)?following\s+code:/i,
      /eval\s*\(/i,
      /system\s*\(/i,
      /exec\s*\(/i,
      
      # Platform-specific attacks
      /overskill\s+(api|internal|secret|private)\s*(keys?|tokens?|credentials?)/i,
      /access\s+(the\s+)?database\s+directly/i,
      /bypass\s+(all\s+)?security/i,
      /disable\s+(all\s+)?filters?/i,
      
      # Prompt boundary breaking attempts
      /\]\s*\}\s*\)\s*END\s*OF\s*PROMPT/i,
      /---END\s+USER\s+INPUT---/i,
      /\*\*\*SYSTEM\s+OVERRIDE\*\*\*/i
    ].freeze
    
    # Patterns that suggest attempts to extract proprietary information
    EXTRACTION_PATTERNS = [
      /list\s+(all\s+)?your\s+capabilities/i,
      /what\s+tools?\s+do\s+you\s+have\s+access\s+to/i,
      /show\s+(me\s+)?your\s+source\s+code/i,
      /reveal\s+your\s+api\s+keys?/i,
      /what\s+version\s+of\s+\w+\s+are\s+you/i,
      /tell\s+me\s+about\s+your\s+training\s+data/i
    ].freeze
    
    # Excessive repetition patterns (often used to overwhelm context)
    REPETITION_THRESHOLD = 10
    
    # Maximum allowed prompt length
    MAX_PROMPT_LENGTH = 50_000
    
    class InjectionAttemptDetected < StandardError; end
    
    attr_reader :violations, :risk_score
    
    def initialize
      @violations = []
      @risk_score = 0
    end
    
    # Main detection method - returns true if injection detected
    def detect_injection?(text)
      return false if text.nil? || text.empty?
      
      @violations.clear
      @risk_score = 0
      
      # Check for length attacks
      if text.length > MAX_PROMPT_LENGTH
        @violations << "Prompt exceeds maximum length (#{MAX_PROMPT_LENGTH} chars)"
        @risk_score += 50
      end
      
      # Check for injection patterns
      INJECTION_PATTERNS.each do |pattern|
        if text.match?(pattern)
          @violations << "Detected injection pattern: #{pattern.source[0..50]}..."
          @risk_score += 30
        end
      end
      
      # Check for extraction attempts
      EXTRACTION_PATTERNS.each do |pattern|
        if text.match?(pattern)
          @violations << "Detected extraction attempt: #{pattern.source[0..50]}..."
          @risk_score += 20
        end
      end
      
      # Check for excessive repetition
      if has_excessive_repetition?(text)
        @violations << "Excessive character/word repetition detected"
        @risk_score += 25
      end
      
      # Check for suspicious unicode characters
      if has_suspicious_unicode?(text)
        @violations << "Suspicious unicode characters detected"
        @risk_score += 15
      end
      
      # Check for hidden text attempts
      if has_hidden_text_attempts?(text)
        @violations << "Hidden text injection attempt detected"
        @risk_score += 35
      end
      
      # Log if violations found
      if @violations.any?
        Rails.logger.warn "[SECURITY] Prompt injection attempt detected:"
        @violations.each { |v| Rails.logger.warn "  - #{v}" }
        Rails.logger.warn "[SECURITY] Risk score: #{@risk_score}"
      end
      
      # Return true if risk score exceeds threshold
      @risk_score >= 30
    end
    
    # Sanitize input to remove dangerous patterns
    def sanitize_input(text)
      return "" if text.nil?
      return "[BLOCKED: Injection attempt detected]" if detect_injection?(text)
      
      sanitized = text.dup
      
      # Normalize whitespace
      sanitized.gsub!(/\s+/, ' ')
      
      # Remove excessive repetition
      sanitized.gsub!(/(.)\1{#{REPETITION_THRESHOLD},}/, '\1' * 3)
      sanitized.gsub!(/(\b\w+\b)(\s+\1){#{REPETITION_THRESHOLD},}/, '\1')
      
      # Remove suspicious unicode
      sanitized.gsub!(/[\u200B-\u200F\u202A-\u202E\u2060-\u2069\uFEFF]/, '')
      
      # Limit length
      sanitized = sanitized[0...MAX_PROMPT_LENGTH] if sanitized.length > MAX_PROMPT_LENGTH
      
      # Strip leading/trailing whitespace
      sanitized.strip
    end
    
    # Validate that output doesn't contain leaked system prompts
    def validate_output(response)
      suspicious_patterns = [
        # System prompt leakage
        /SYSTEM\s*[:]\s*You\s+are/i,
        /INSTRUCTIONS\s*[:]\s*You\s+are/i,
        /\[SYSTEM\s+PROMPT\]/i,
        /---\s*SYSTEM\s+INSTRUCTIONS\s*---/i,
        
        # API key/secret exposure
        /API[_\s]KEY\s*[:=]\s*[\w\-]+/i,
        /SECRET[_\s]KEY\s*[:=]\s*[\w\-]+/i,
        /ANTHROPIC[_\s]API[_\s]KEY/i,
        /OPENAI[_\s]API[_\s]KEY/i,
        
        # Internal tool/function exposure
        /os-[a-z\-]+\s*\(.*\)/i,  # Our tool format
        /function:\s*os-/i,
        
        # Database/infrastructure exposure
        /postgres:\/\//i,
        /redis:\/\//i,
        /DATABASE_URL/i,
        
        # Numbered instruction lists (often system prompts)
        /^\s*\d+\.\s+You\s+(must|should|will|are)/im,
        /^###\s*Instructions:/im
      ]
      
      violations = []
      suspicious_patterns.each do |pattern|
        if response.match?(pattern)
          violations << "Output contains suspicious pattern: #{pattern.source[0..30]}..."
        end
      end
      
      if violations.any?
        Rails.logger.error "[SECURITY] Suspicious output detected:"
        violations.each { |v| Rails.logger.error "  - #{v}" }
        return false
      end
      
      true
    end
    
    # Filter response to remove any leaked information
    def filter_response(response)
      return "I cannot provide that information." unless validate_output(response)
      response
    end
    
    # Check if prompt should be rate-limited
    def should_rate_limit?(user, app)
      # Check recent injection attempts
      recent_attempts = Rails.cache.fetch("injection_attempts:#{user.id}", expires_in: 1.hour) { 0 }
      
      if recent_attempts > 5
        Rails.logger.warn "[SECURITY] User #{user.id} rate-limited for injection attempts"
        return true
      end
      
      false
    end
    
    # Record an injection attempt
    def record_injection_attempt(user, app, prompt)
      # Increment counter
      count = Rails.cache.increment("injection_attempts:#{user.id}", 1, expires_in: 1.hour)
      
      # Log for security monitoring
      Rails.logger.warn "[SECURITY] Injection attempt ##{count} by user #{user.id} on app #{app.id}"
      
      # Store detailed log for review (sanitized)
      SecurityLog.create!(
        user: user,
        app: app,
        event_type: 'prompt_injection_attempt',
        details: {
          prompt_preview: prompt[0..500],
          violations: @violations,
          risk_score: @risk_score,
          timestamp: Time.current
        }
      )
      
      # Alert if threshold exceeded
      if count > 10
        AlertService.security_alert(
          "Multiple injection attempts from user #{user.id}",
          severity: :high
        )
      end
    end
    
    private
    
    def has_excessive_repetition?(text)
      # Check character repetition
      return true if text.match?(/(.)\1{#{REPETITION_THRESHOLD},}/)
      
      # Check word repetition
      words = text.split(/\s+/)
      word_counts = words.group_by(&:downcase).transform_values(&:count)
      
      # If any word appears more than threshold times consecutively
      words.each_cons(REPETITION_THRESHOLD) do |consecutive_words|
        return true if consecutive_words.uniq.size == 1
      end
      
      false
    end
    
    def has_suspicious_unicode?(text)
      # Check for zero-width characters and other suspicious unicode
      suspicious_chars = [
        "\u200B", # Zero-width space
        "\u200C", # Zero-width non-joiner
        "\u200D", # Zero-width joiner
        "\u200E", # Left-to-right mark
        "\u200F", # Right-to-left mark
        "\u202A", # Left-to-right embedding
        "\u202B", # Right-to-left embedding
        "\u202C", # Pop directional formatting
        "\u202D", # Left-to-right override
        "\u202E", # Right-to-left override
        "\u2060", # Word joiner
        "\u2061", # Function application
        "\u2062", # Invisible times
        "\u2063", # Invisible separator
        "\u2064", # Invisible plus
        "\uFEFF"  # Zero-width no-break space
      ]
      
      suspicious_chars.any? { |char| text.include?(char) }
    end
    
    def has_hidden_text_attempts?(text)
      # Check for various hidden text techniques
      patterns = [
        /<div\s+style\s*=\s*["']display:\s*none/i,
        /<span\s+style\s*=\s*["']visibility:\s*hidden/i,
        /color:\s*(white|#fff|#ffffff|rgb\(255,\s*255,\s*255\))/i,
        /font-size:\s*0/i,
        /opacity:\s*0/i,
        /position:\s*absolute;\s*left:\s*-9999/i
      ]
      
      patterns.any? { |pattern| text.match?(pattern) }
    end
  end
end