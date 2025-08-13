module MarkdownHelper
  def render_markdown(text)
    return "" if text.blank?
    
    # First escape any HTML-like content that isn't markdown
    text = escape_html_like_content(text)
    
    # Configure Redcarpet with safe options
    renderer = Redcarpet::Render::HTML.new(
      filter_html: true,          # Filter out HTML tags
      no_styles: true,            # Don't allow style attributes
      safe_links_only: true,      # Only allow safe protocols
      with_toc_data: false,       # Don't add TOC anchors
      hard_wrap: true,            # Add <br> for line breaks
      link_attributes: { target: '_blank', rel: 'noopener' }
    )
    
    markdown = Redcarpet::Markdown.new(renderer, {
      autolink: true,             # Auto-convert URLs to links
      tables: true,               # Enable tables
      fenced_code_blocks: true,   # Enable ``` code blocks
      lax_spacing: true,          # Allow single line breaks
      no_intra_emphasis: true,    # Don't parse _ inside words
      strikethrough: true,        # Enable ~~strikethrough~~
      superscript: true,          # Enable ^superscript
      highlight: true,            # Enable ==highlight==
      quote: true,                # Enable "quote"
      footnotes: false            # Disable footnotes for safety
    })
    
    # Render markdown to HTML
    html = markdown.render(text)
    
    # Add Tailwind classes to elements
    html = add_tailwind_classes(html)
    
    # Convert emoji shortcuts to icons
    html = convert_emoji_to_icons(html)
    
    html.html_safe
  end
  
  def extract_suggestions_from_markdown(content)
    suggestions = []
    
    # Look for the Quick actions section
    if content.match(/\*\*Quick actions:\*\*\n(.*?)(?:\n\n|$)/m)
      actions_text = $1
      actions_text.split("\n").each do |line|
        # Match pattern like [🔧 Fix something]: Do this specific thing
        if match = line.match(/\[(.*?)\]:\s*(.*)/)
          label = match[1]
          prompt = match[2]
          
          # Extract icon and clean label
          icon = nil
          clean_label = label
          
          if label.match(/^(🔧|✨|🎨|📱|⚡|🎯|📊|🔔|💾)\s+(.+)/)
            icon = $1
            clean_label = $2
          end
          
          suggestions << {
            label: clean_label,
            prompt: prompt,
            icon: icon
          }
        end
      end
    end
    
    suggestions
  end
  
  def extract_bugs_from_markdown(content)
    bugs = []
    
    # Look for potential issues section
    if content.match(/⚠️ \*\*Potential issues.*?:\*\*\n(.*?)(?:\n\n|$)/m)
      bugs_text = $1
      bugs_text.split("\n").each do |line|
        if line.start_with?("- ", "• ")
          bug_text = line.sub(/^[•\-]\s*/, '')
          # Extract file reference if present
          if bug_text.match(/(.+?)\s*\((.+?)\)$/)
            bugs << { message: $1, file: $2 }
          else
            bugs << { message: bug_text }
          end
        end
      end
    end
    
    bugs
  end
  
  private
  
  def escape_html_like_content(text)
    # Escape HTML-like tags that aren't common markdown (like <title>, <TCPSocket:, etc.)
    # but preserve common markdown-ish patterns
    
    # List of HTML tags we want to escape (not commonly used in markdown)
    html_tags_to_escape = %w[
      title meta link script style body html head div span p br hr img input form button
      table tr td th ul ol li a strong em b i u del ins sub sup blockquote pre code
      h1 h2 h3 h4 h5 h6 canvas svg path circle rect line text g defs clipPath mask
      TCPSocket
    ]
    
    # Escape HTML-like content but preserve actual markdown
    escaped_text = text.dup
    
    # Escape angle brackets that look like HTML tags
    html_tags_to_escape.each do |tag|
      # Match opening tags like <title> or <TCPSocket:(...)>
      escaped_text.gsub!(/<#{Regexp.escape(tag)}[^>]*>/i) do |match|
        ERB::Util.html_escape(match)
      end
      # Match closing tags like </title>
      escaped_text.gsub!(/<\/#{Regexp.escape(tag)}>/i) do |match|
        ERB::Util.html_escape(match)
      end
    end
    
    # Also escape standalone angle brackets that might break HTML
    escaped_text.gsub!(/<([^a-zA-Z\/!?])/, '&lt;\1')
    escaped_text.gsub!(/([^a-zA-Z\/!?])>/, '\1&gt;')
    
    escaped_text
  end
  
  def add_tailwind_classes(html)
    # Headers - optimized for structured content like implementation plans
    html.gsub!(/<h1>/, '<h1 class="text-lg font-bold text-gray-900 dark:text-gray-100 mt-4 mb-2 border-b border-gray-200 dark:border-gray-700 pb-1">')
    html.gsub!(/<h2>/, '<h2 class="text-base font-semibold text-gray-900 dark:text-gray-100 mt-3 mb-2">')
    html.gsub!(/<h3>/, '<h3 class="text-sm font-medium text-gray-900 dark:text-gray-100 mt-2 mb-1">')
    
    # Paragraphs - better spacing for readability
    html.gsub!(/<p>/, '<p class="mb-2 text-sm leading-relaxed">')
    
    # Lists - improved structure and spacing
    html.gsub!(/<ul>/, '<ul class="space-y-1 my-2 text-sm">')
    html.gsub!(/<ol>/, '<ol class="space-y-1 my-2 text-sm">')
    
    # List items - better bullet styling and spacing
    html.gsub!(/<li>/, '<li class="flex items-start space-x-2 pl-0">')
    
    # Add custom bullets for unordered lists
    html.gsub!(/(<ul[^>]*>.*?)<li class="flex items-start space-x-2 pl-0">/m) do
      "#{$1}<li class=\"flex items-start space-x-2 pl-0\"><span class=\"text-gray-400 dark:text-gray-500 mt-0.5 text-xs\">•</span><span class=\"flex-1\">"
    end
    
    # Close span for list items in unordered lists
    html.gsub!(/(<ul[^>]*>.*?<\/span><span class="flex-1">.*?)<\/li>/m) do
      "#{$1}</span></li>"
    end
    
    # Add custom numbers for ordered lists  
    html.gsub!(/(<ol[^>]*>.*?)<li class="flex items-start space-x-2 pl-0">/m) do |match|
      # Count existing li elements to get the number
      li_count = match.scan(/<li/).length
      "#{match.gsub(/<li class="flex items-start space-x-2 pl-0">$/, '')}<li class=\"flex items-start space-x-2 pl-0\"><span class=\"text-gray-500 dark:text-gray-400 mt-0.5 text-xs font-medium min-w-[1rem]\">#{li_count}.</span><span class=\"flex-1\">"
    end
    
    # Close span for list items in ordered lists
    html.gsub!(/(<ol[^>]*>.*?<\/span><span class="flex-1">.*?)<\/li>/m) do
      "#{$1}</span></li>"
    end
    
    # Nested lists - reduce left margin
    html.gsub!(/<ul class="space-y-1 my-2 text-sm">([^<]*<li[^>]*>[^<]*<ul)/m) do
      "<ul class=\"space-y-0.5 my-1 text-sm ml-4\">#{$1.gsub('<ul class="space-y-1 my-2 text-sm">', '<ul class="space-y-0.5 my-1 text-sm ml-4">')}"
    end
    
    # Code blocks - better styling
    html.gsub!(/<pre>/, '<pre class="bg-gray-50 dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg p-3 overflow-x-auto my-2 text-xs">')
    html.gsub!(/<code>/, '<code class="text-xs text-gray-800 dark:text-gray-200 font-mono">')
    
    # Inline code - improved visibility
    html.gsub!(/(<p[^>]*>.*?)<code>(.+?)<\/code>(.*?<\/p>)/m) do
      "#{$1}<code class=\"bg-gray-100 dark:bg-gray-800 text-gray-800 dark:text-gray-200 px-1.5 py-0.5 rounded text-xs font-mono border border-gray-200 dark:border-gray-600\">#{$2}</code>#{$3}"
    end
    
    # Links - better contrast
    html.gsub!(/<a /, '<a class="text-blue-600 dark:text-blue-400 hover:text-blue-800 dark:hover:text-blue-300 underline decoration-dotted hover:decoration-solid transition-colors" ')
    
    # Strong/Bold - enhanced for headers and emphasis
    html.gsub!(/<strong>/, '<strong class="font-semibold text-gray-900 dark:text-gray-100">')
    
    # Blockquotes - improved styling
    html.gsub!(/<blockquote>/, '<blockquote class="border-l-4 border-blue-200 dark:border-blue-800 bg-blue-50 dark:bg-blue-900/10 pl-4 py-2 my-3 italic text-gray-700 dark:text-gray-300 rounded-r-md">')
    
    # Tables - add responsive styling
    html.gsub!(/<table>/, '<table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700 my-3 text-sm">')
    html.gsub!(/<th>/, '<th class="px-3 py-2 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider bg-gray-50 dark:bg-gray-800">')
    html.gsub!(/<td>/, '<td class="px-3 py-2 whitespace-nowrap text-sm text-gray-900 dark:text-gray-100">')
    
    html
  end
  
  def convert_emoji_to_icons(html)
    # Map emoji to Font Awesome icons
    emoji_map = {
      '🔧' => '<i class="fas fa-wrench text-gray-600 dark:text-gray-400"></i>',
      '✨' => '<i class="fas fa-sparkles text-yellow-500"></i>',
      '🎨' => '<i class="fas fa-palette text-purple-500"></i>',
      '📱' => '<i class="fas fa-mobile-alt text-green-500"></i>',
      '⚡' => '<i class="fas fa-bolt text-yellow-500"></i>',
      '🎯' => '<i class="fas fa-bullseye text-red-500"></i>',
      '📊' => '<i class="fas fa-chart-bar text-blue-500"></i>',
      '🔔' => '<i class="fas fa-bell text-indigo-500"></i>',
      '💾' => '<i class="fas fa-save text-gray-600"></i>',
      '📋' => '<i class="fas fa-clipboard text-blue-500"></i>',
      '🧠' => '<i class="fas fa-brain text-purple-500"></i>',
      '💭' => '<i class="fas fa-thought-bubble text-gray-500"></i>',
      '⚠️' => '<i class="fas fa-exclamation-triangle text-yellow-500"></i>',
      '❌' => '<i class="fas fa-times-circle text-red-500"></i>',
      '✅' => '<i class="fas fa-check-circle text-green-500"></i>'
    }
    
    emoji_map.each do |emoji, icon|
      html.gsub!(emoji, icon)
    end
    
    html
  end
end