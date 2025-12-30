# frozen_string_literal: true

module ReleaseHx
  module Transforms
    # Converts Atlassian Document Format (ADF) to Markdown.
    # Focused on extracting "Release Note" sections from Jira issue descriptions
    # and converting them to clean Markdown for use in release documentation.
    module AdfToMarkdown
      # Checks if an object is an ADF document
      #
      # @param obj [Object] The object to check
      # @return [Boolean] true if obj is an ADF document
      def self.adf? obj
        return false unless obj.is_a?(Hash)
        return false unless obj['type'] == 'doc'
        return false unless obj['version'] == 1

        obj.key?('content') && obj['content'].is_a?(Array)
      end

      # Extracts a specific section from an ADF document by heading text
      #
      # @param adf_doc [Hash] The ADF document
      # @param heading [String] The heading text to search for (case-insensitive)
      # @return [Hash] A new ADF document containing only the extracted section
      def self.extract_section adf_doc, heading: 'Release Note'
        return adf_doc unless adf?(adf_doc)

        content = adf_doc['content'] || []
        heading_normalized = heading.strip.downcase

        # Find the heading index
        heading_idx = content.find_index do |node|
          node['type'] == 'heading' &&
            extract_text_from_node(node).strip.downcase == heading_normalized
        end

        return { 'type' => 'doc', 'version' => 1, 'content' => [] } unless heading_idx

        # Extract nodes after the heading until next same-level or higher heading
        heading_level = content[heading_idx].dig('attrs', 'level') || 1
        section_content = []

        ((heading_idx + 1)...content.length).each do |i|
          node = content[i]

          # Stop if we hit another heading at same or higher level
          if node['type'] == 'heading'
            node_level = node.dig('attrs', 'level') || 1
            break if node_level <= heading_level
          end

          section_content << node
        end

        { 'type' => 'doc', 'version' => 1, 'content' => section_content }
      end

      # Converts an ADF document (or fragment) to Markdown
      #
      # @param adf_doc [Hash] The ADF document to convert
      # @param options [Hash] Conversion options
      # @option options [Array<String>] :exclude_nodes Node types to exclude
      # @return [String] The Markdown representation
      def self.convert adf_doc, options = {}
        return '' unless adf?(adf_doc)

        excluded = options[:exclude_nodes] || default_excluded_nodes
        content = adf_doc['content'] || []

        converted = content.map { |node| convert_node(node, excluded) }
        converted.join.strip
      end

      # Default nodes to exclude (headings, media, mentions, etc.)
      def self.default_excluded_nodes
        %w[heading media mediaGroup mediaSingle mediaInline mention emoji status inlineCard blockCard date]
      end

      # Converts a single ADF node to Markdown
      #
      # @param node [Hash] The ADF node
      # @param excluded [Array<String>] Node types to exclude
      # @param depth [Integer] Current nesting depth for lists
      # @return [String] The Markdown representation
      def self.convert_node node, excluded = [], depth = 0
        return '' unless node.is_a?(Hash)
        return '' if excluded.include?(node['type'])

        case node['type']
        when 'doc'
          content = node['content'] || []
          content.map { |n| convert_node(n, excluded, depth) }.join
        when 'paragraph'
          "#{convert_paragraph(node, excluded)}\n\n"
        when 'bulletList'
          convert_list(node, excluded, depth, unordered: true)
        when 'orderedList'
          convert_list(node, excluded, depth, unordered: false)
        when 'listItem'
          convert_list_item(node, excluded, depth)
        when 'codeBlock'
          convert_code_block(node)
        when 'blockquote'
          convert_blockquote(node, excluded)
        when 'panel'
          convert_panel(node, excluded)
        when 'rule'
          "\n---\n\n"
        when 'table'
          convert_table(node, excluded)
        when 'tableRow'
          convert_table_row(node, excluded)
        when 'tableHeader', 'tableCell'
          convert_table_cell(node, excluded)
        when 'text'
          apply_marks(node)
        when 'hardBreak'
          "  \n"
        when 'taskList'
          convert_task_list(node, excluded, depth)
        when 'taskItem'
          convert_task_item(node, excluded, depth)
        else
          # For unknown nodes, try to extract text content
          ReleaseHx.logger.debug "Skipping unsupported ADF node type: #{node['type']}"
          extract_text_from_node(node)
        end
      end

      # Converts a paragraph node
      def self.convert_paragraph node, excluded
        content = node['content'] || []
        content.map { |n| convert_node(n, excluded) }.join
      end

      # Converts a list (bullet or ordered)
      def self.convert_list node, excluded, depth, unordered: true
        content = node['content'] || []
        items = content.map { |item| convert_node(item, excluded, depth + 1) }
        "#{items.join}\n"
      end

      # Converts a list item
      def self.convert_list_item node, excluded, depth
        content = node['content'] || []
        indent = '  ' * (depth - 1)
        marker = '- '

        # Separate paragraph content from nested lists
        paragraphs = []
        nested_lists = []

        content.each do |n|
          if n['type'] == 'paragraph'
            paragraphs << convert_paragraph(n, excluded).strip
          elsif %w[bulletList orderedList].include?(n['type'])
            nested_lists << convert_node(n, excluded, depth)
          else
            paragraphs << convert_node(n, excluded, depth).strip
          end
        end

        # Build the list item line
        result = "#{indent}#{marker}#{paragraphs.join(' ')}\n"

        # Add nested lists on new lines with proper indentation
        nested_lists.each do |nested|
          result += nested
        end

        result
      end

      # Converts a code block
      def self.convert_code_block node
        lang = node.dig('attrs', 'language') || ''
        content = node['content'] || []
        code = content.map { |n| n['type'] == 'text' ? n['text'] : '' }.join

        "```#{lang}\n#{code}\n```\n\n"
      end

      # Converts a blockquote
      def self.convert_blockquote node, excluded
        content = node['content'] || []
        lines = content.map { |n| convert_node(n, excluded).strip }.join("\n")
        quoted = lines.split("\n").map { |line| "> #{line}" }.join("\n")
        "#{quoted}\n\n"
      end

      # Converts a panel to a blockquote with admonition label
      def self.convert_panel node, excluded
        panel_type = node.dig('attrs', 'panelType') || 'info'
        label = panel_type_to_label(panel_type)

        content = node['content'] || []
        text = content.map { |n| convert_node(n, excluded).strip }.join("\n")

        "> **#{label}:** #{text}\n\n"
      end

      # Maps panel types to admonition labels
      def self.panel_type_to_label panel_type
        {
          'info' => 'NOTE',
          'note' => 'NOTE',
          'warning' => 'WARNING',
          'error' => 'CAUTION',
          'success' => 'TIP'
        }[panel_type] || 'NOTE'
      end

      # Converts a table (basic GFM table support)
      def self.convert_table node, excluded
        content = node['content'] || []
        return '' if content.empty?

        # Check if first row contains headers
        first_row = content[0]
        has_header = first_row && first_row['content']&.any? { |cell| cell['type'] == 'tableHeader' }

        rows = content.map { |row| convert_node(row, excluded) }

        if has_header
          header = rows[0]
          # Create separator row
          col_count = first_row['content']&.length || 0
          separator = "|#{' --- |' * col_count}\n"
          table_body = rows[1..].join

          "#{header}#{separator}#{table_body}\n"
        else
          "#{rows.join}\n"
        end
      end

      # Converts a table row
      def self.convert_table_row node, excluded
        content = node['content'] || []
        cells = content.map { |cell| convert_node(cell, excluded) }
        "| #{cells.join(' | ')} |\n"
      end

      # Converts a table cell
      def self.convert_table_cell node, excluded
        content = node['content'] || []
        content.map { |n| convert_node(n, excluded).strip }.join(' ')
      end

      # Converts a task list
      def self.convert_task_list node, excluded, depth
        content = node['content'] || []
        content.map { |item| convert_node(item, excluded, depth + 1) }.join
      end

      # Converts a task item
      def self.convert_task_item node, excluded, depth
        state = node.dig('attrs', 'state')
        marker = state == 'DONE' ? '[x]' : '[ ]'
        indent = '  ' * (depth - 1)

        content = node['content'] || []
        text = content.map { |n| convert_node(n, excluded, depth).strip }.join(' ')

        "#{indent}- #{marker} #{text}\n"
      end

      # Apply marks (bold, italic, code, link) to text
      def self.apply_marks node
        text = node['text'] || ''
        marks = node['marks'] || []

        marks.each do |mark|
          case mark['type']
          when 'strong'
            text = "**#{text}**"
          when 'em'
            text = "_#{text}_"
          when 'code'
            text = "`#{text}`"
          when 'link'
            href = mark.dig('attrs', 'href') || ''
            text = "[#{text}](#{href})"
          when 'strike'
            text = "~~#{text}~~"
          when 'underline'
            # Markdown doesn't have native underline; use HTML
            text = "<u>#{text}</u>"
          end
        end

        text
      end

      # Extract plain text from any node (recursive)
      def self.extract_text_from_node node
        return '' unless node.is_a?(Hash)

        return node['text'] || '' if node['type'] == 'text'

        content = node['content'] || []
        content.map { |n| extract_text_from_node(n) }.join
      end
    end
  end
end
