# This module will likely spin off into a gem

# frozen_string_literal: true

require 'asciidoctor'

module Sourcerer
  # A custom Asciidoctor converter that outputs plain text.
  # It is registered for the "plaintext" backend and can be used to extract
  # the raw text content or attributes from an AsciiDoc document.
  class PlainTextConverter < Asciidoctor::Converter::Base
    # Identify ourselves as a converter for the "plaintext" backend
    register_for 'plaintext'

    # The main entry point for the converter.
    # It is called by Asciidoctor to convert a node.
    #
    # @param node [Asciidoctor::AbstractNode] The node to convert.
    # @param _transform [String] The transform to apply (unused).
    # @param _opts [Hash] Options for the conversion (unused).
    # @return [String] The converted plain text output.
    def convert node, _transform = nil, _opts = {}
      if respond_to?("convert_#{node.node_name}", true)
        send("convert_#{node.node_name}", node)
      elsif node.respond_to?(:content)
        node.content.to_s
      elsif node.respond_to?(:text)
        node.text.to_s
      else
        ''
      end
    end

    private

    # Converts the document node.
    def convert_document node
      emit_attrs = node.attr('sourcerer_mode') == 'emit_attrs'

      if emit_attrs
        # only emit attribute lines directly, nothing else
        attrs = node.attributes.select do |k, v|
          k.is_a?(String) && !v.nil? && !k.start_with?('backend-', 'safe-mode', 'doctype', 'sourcerer_mode')
        end

        formatted_attrs = attrs.map { |k, v| ":#{k}: #{v}" }
        formatted_attrs.join("\n") # NO EXTRA SPACES OR LINES
      else
        node.blocks.map { |block| convert block }.join("\n")
      end
    end

    # Converts a section node.
    def convert_section node
      title = node.title? ? node.title : ''
      body = node.blocks.map { |block| convert block }.join("\n")
      [title, body].reject(&:empty?).join("\n")
    end

    # Converts a paragraph node.
    def convert_paragraph node
      node.lines.join("\n")
    end

    # Converts a listing node.
    def convert_listing node
      node.content
    end

    # Converts a literal node.
    def convert_literal node
      node.content
    end
  end
end
