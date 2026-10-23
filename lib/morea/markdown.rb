# frozen_string_literal: true

require "erb"

module Morea
  # Small, dependency-free Markdown renderer for content pages. Input is HTML-escaped
  # first, so only the tags emitted here can reach the page. Supports headings, bold,
  # italic, links, bullet/numbered lists, quotes, rules, and paragraphs (single
  # newlines become <br>, as plain-text pages always did).
  module Markdown
    SAFE_URL = %r{\A(https?://|mailto:|tel:|/|#)}i

    module_function

    def render(text)
      text.to_s.gsub("\r\n", "\n").strip.split(/\n{2,}/).filter_map { |block| render_block(block.strip) }.join("\n").html_safe
    end

    def render_block(block)
      lines = block.split("\n")
      case block
      when /\A(\#{1,6})\s+(.+)\z/m
        level = $1.length.clamp(2, 6) # the page title is the h1
        "<h#{level}>#{inline($2.strip)}</h#{level}>"
      when /\A([-*_])(\s*\1){2,}\z/
        "<hr>"
      else
        if lines.all? { |l| l.match?(/\A\s*[-*+]\s+/) }
          list("ul", lines.map { |l| l.sub(/\A\s*[-*+]\s+/, "") })
        elsif lines.all? { |l| l.match?(/\A\s*\d+[.)]\s+/) }
          list("ol", lines.map { |l| l.sub(/\A\s*\d+[.)]\s+/, "") })
        elsif lines.all? { |l| l.start_with?(">") }
          "<blockquote>#{lines.map { |l| inline(l.sub(/\A>\s?/, "")) }.join("<br>")}</blockquote>"
        else
          "<p>#{lines.map { |l| inline(l.strip) }.join("<br>")}</p>"
        end
      end
    end

    def list(tag, items)
      "<#{tag}>#{items.map { |i| "<li>#{inline(i)}</li>" }.join}</#{tag}>"
    end

    def inline(text)
      html = ERB::Util.html_escape(text).to_s
      html = html.gsub(/\[([^\]]+)\]\(([^)\s]+)\)/) do
        label = $1
        url = $2
        url.match?(SAFE_URL) ? %(<a href="#{url}">#{label}</a>) : label
      end
      html.gsub(/\*\*(.+?)\*\*|__(.+?)__/) { "<strong>#{$1 || $2}</strong>" }
          .gsub(/(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])|(?<!\w)_(?!\s)(.+?)(?<!\s)_(?!\w)/) { "<em>#{$1 || $2}</em>" }
    end
  end
end
