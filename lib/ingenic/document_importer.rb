# frozen_string_literal: true

require "stringio"

module Ingenic
  # Turns an uploaded document into one page of a version.
  #
  # The administration screen can already write a page by hand. This is for the
  # manual a team already has as files: a Markdown file is stored as it is, and a
  # Word file is read into Markdown first. One file becomes one page — the tree
  # (series -> chip -> version -> pages) is a decision about the manual, not
  # something a heading level can infer reliably.
  #
  # A leading `# Title` is taken out of the body and used as the page title,
  # because the reader already draws the title above the body.
  class DocumentImporter
    MAX_BYTES = 5.megabytes
    MARKDOWN_EXTENSIONS = %w[.md .markdown .txt].freeze
    WORD_EXTENSIONS = %w[.docx].freeze
    WORD_NAMESPACE = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"

    class ImportError < StandardError; end

    def initialize(version)
      @version = version
    end

    def import(file)
      filename = file.original_filename.to_s
      extension = File.extname(filename).downcase

      unless MARKDOWN_EXTENSIONS.include?(extension) || WORD_EXTENSIONS.include?(extension)
        raise ImportError, I18n.t("ingenic.import.unsupported")
      end

      if file.tempfile.size > MAX_BYTES
        raise ImportError, I18n.t("ingenic.import.too_large")
      end

      content =
        if WORD_EXTENSIONS.include?(extension)
          docx_to_markdown(file.tempfile.read)
        else
          file.tempfile.read.force_encoding("UTF-8")
        end

      title, body = split_title(content, filename, extension)

      page = IngenicDocPage.new(
        version: @version,
        parent_id: nil,
        slug: available_slug(filename, title),
        title: title,
        body: body,
        published: true,
        position: next_position,
      )
      page.save!
      page
    end

    private

    attr_reader :version

    def next_position
      (version.pages.maximum(:position) || -1) + 1
    end

    # The title is the first ATX heading if there is one; the file name is the
    # fallback, because a file without any heading still has a name the author
    # chose.
    def split_title(content, filename, extension)
      text = content.to_s.sub(/\A﻿/, "")
      lines = text.lines

      if (heading = lines.find { |line| line.match?(/\A\s*#\s+\S/) })
        index = lines.index(heading)
        title = heading.sub(/\A\s*#\s+/, "").strip
        body = (lines[0...index] + lines[(index + 1)..]).join.sub(/\A\s*\n+/, "").rstrip
        [title, body]
      else
        title = File.basename(filename, extension).tr("_-", " ").strip.presence ||
          I18n.t("ingenic.import.default_title")
        [title, text.rstrip]
      end
    end

    def available_slug(filename, title)
      base = File.basename(filename, File.extname(filename)).parameterize.presence ||
        title.to_s.parameterize.presence ||
        "page"

      candidate = base
      suffix = 2
      while IngenicDocPage.exists?(version_id: version.id, slug: candidate)
        candidate = "#{base}-#{suffix}"
        suffix += 1
      end
      candidate
    end

    # A .docx is a zip with the text in word/document.xml. The subset handled
    # here is what a manual is made of: headings, paragraphs, bold and italic
    # runs, bullets and tables. Anything else is kept as its text, so a file
    # never imports as an empty page.
    def docx_to_markdown(data)
      require "zip"

      xml = nil
      Zip::File.open_buffer(StringIO.new(data)) do |zip|
        entry = zip.find_entry("word/document.xml")
        raise ImportError, I18n.t("ingenic.import.unreadable") if entry.nil?

        xml = entry.get_input_stream.read
      end

      document = Nokogiri::XML(xml)
      lines = []

      document.xpath("//w:body/*", "w" => WORD_NAMESPACE).each do |node|
        case node.name
        when "p"
          lines << paragraph_markdown(node)
        when "tbl"
          lines.concat(table_markdown(node))
          lines << ""
        end
      end

      lines.join("\n").gsub(/\n{3,}/, "\n\n").strip
    rescue Zip::Error, Nokogiri::XML::SyntaxError
      raise ImportError, I18n.t("ingenic.import.unreadable")
    end

    def paragraph_markdown(node)
      text = runs_markdown(node)
      return "" if text.empty?

      style = node.at_xpath("./w:pPr/w:pStyle/@w:val", "w" => WORD_NAMESPACE)&.value.to_s
      level = heading_level(style)
      return "#{'#' * level} #{text}" if level

      return "- #{text}" if node.at_xpath("./w:pPr/w:numPr", "w" => WORD_NAMESPACE)

      text
    end

    def heading_level(style)
      return 1 if style.casecmp("title").zero?

      match = style.match(/\Aheading\s*([1-6])\z/i)
      match && match[1].to_i
    end

    def runs_markdown(node)
      node.xpath(".//w:r", "w" => WORD_NAMESPACE).map do |run|
        text = run.xpath(".//w:t", "w" => WORD_NAMESPACE).map(&:text).join
        next "" if text.empty?

        properties = run.at_xpath("./w:rPr", "w" => WORD_NAMESPACE)
        text = "**#{text}**" if properties&.at_xpath("./w:b", "w" => WORD_NAMESPACE)
        text = "*#{text}*" if properties&.at_xpath("./w:i", "w" => WORD_NAMESPACE)
        text
      end.join.strip
    end

    def table_markdown(node)
      rows = node.xpath("./w:tr", "w" => WORD_NAMESPACE).map do |row|
        row.xpath("./w:tc", "w" => WORD_NAMESPACE).map do |cell|
          cell.xpath(".//w:p", "w" => WORD_NAMESPACE)
            .map { |paragraph| runs_markdown(paragraph) }
            .reject(&:empty?)
            .join(" ")
            .gsub("|", "\\|")
        end
      end

      rows.reject! { |row| row.all?(&:empty?) }
      return [] if rows.empty?

      width = rows.map(&:length).max
      lines = rows.map { |row| "| #{row.fill("", row.length...width).join(" | ")} |" }
      lines.insert(1, "| #{Array.new(width, "---").join(" | ")} |")
      lines
    end
  end
end
