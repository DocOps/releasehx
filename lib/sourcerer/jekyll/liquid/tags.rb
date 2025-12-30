# frozen_string_literal: true

module Sourcerer
  module Jekyll
    # This module contains custom Liquid tags for the Sourcerer templating environment.
    module Tags
      # A Liquid tag for embedding and rendering a file within a template.
      # It searches for the file in the configured include paths.
      class EmbedTag < ::Liquid::Tag
        # @param tag_name [String] The name of the tag ('embed').
        # @param markup [String] The name of the partial to embed.
        # @param tokens [Array<String>] The list of tokens.
        def initialize tag_name, markup, tokens
          super
          @partial_name = markup.strip
        end

        # Renders the embedded file.
        #
        # @param context [Liquid::Context] The Liquid context.
        # @return [String] The rendered content of the embedded file.
        # @raise [IOError] if the embed file is not found.
        def render context
          includes_paths = context.registers[:includes_load_paths] || []

          found_path = includes_paths.find do |base|
            candidate = File.expand_path(@partial_name, base)
            File.exist?(candidate)
          end

          raise "Embed file not found: #{@partial_name}" unless found_path

          full_path = File.expand_path(@partial_name, found_path)
          source = File.read(full_path)

          partial = ::Liquid::Template.parse(source)
          partial.render!(context)
        end
      end
    end
  end
end

Liquid::Template.register_tag('embed', Sourcerer::Jekyll::Tags::EmbedTag)
