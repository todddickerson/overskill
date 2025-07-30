module ApplicationHelper
  include Helpers::Base

  def current_theme
    :light
  end

  def file_icon(file_type)
    case file_type
    when "html"
      "fab fa-html5 text-orange-500"
    when "javascript"
      "fab fa-js-square text-yellow-500"
    when "css"
      "fab fa-css3-alt text-blue-500"
    when "json"
      "fas fa-file-code text-gray-400"
    else
      "fas fa-file text-gray-400"
    end
  end

  def html_for_preview(app)
    # Find the main HTML file
    html_file = app.app_files.find_by(file_type: "html") || app.app_files.find_by(path: "index.html")

    if html_file
      # Get all other files
      js_files = app.app_files.where(file_type: "javascript")
      css_files = app.app_files.where(file_type: "css")

      # Start with the HTML content
      html = html_file.content.dup

      # Inject CSS files
      if css_files.any?
        css_content = css_files.map(&:content).join("\n")
        css_tag = "<style>#{css_content}</style>"

        # Insert before closing head or at the beginning
        if html.include?("</head>")
          html.gsub!("</head>", "#{css_tag}\n</head>")
        else
          html = css_tag + "\n" + html
        end
      end

      # Inject JavaScript files
      if js_files.any?
        js_files.each do |js_file|
          # Replace script src references with inline content
          if html.include?(%(src="#{js_file.path}"))
            html.gsub!(%r{<script[^>]*src="#{Regexp.escape(js_file.path)}"[^>]*></script>},
              "<script>#{js_file.content}</script>")
          else
            # Add at the end if not referenced
            js_tag = "<script>#{js_file.content}</script>"
            if html.include?("</body>")
              html.gsub!("</body>", "#{js_tag}\n</body>")
            else
              html += "\n#{js_tag}"
            end
          end
        end
      end

      html.html_safe
    else
      "<p>No HTML file found</p>".html_safe
    end
  end
end
