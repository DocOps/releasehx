# frozen_string_literal: true

require_relative '../loader'
require_relative '../schema_utils'

module SchemaGraphy
  # A module for handling CFGYML, a schema-driven configuration system.
  module CFGYML
    # Represents a configuration definition loaded from a schema file.
    # It provides methods for accessing defaults and rendering documentation.
    class Definition
      # @return [Hash] The loaded schema hash.
      attr_reader :schema

      # @return [Hash] The attributes used for resolving placeholders in the schema.
      attr_reader :attributes

      # @param schema_path [String] The path to the schema YAML file.
      # @param attrs [Hash] A hash of attributes for placeholder resolution.
      def initialize schema_path, attrs = {}
        @schema = Loader.load_yaml_with_attributes(schema_path, attrs)
        @attributes = attrs
      end

      # Extract default values from the loaded schema.
      # @return [Hash] A hash of default values.
      def defaults
        SchemaUtils.crawl_defaults(@schema)
      end

      # Get the search paths for templates.
      # @return [Array<String>] An array of template paths.
      def template_paths
        @template_paths ||= [
          File.join(File.dirname(__FILE__), '..', 'templates', 'cfgyml'),
          *additional_template_paths
        ]
      end

      # Render a configuration reference or sample in the specified format.
      #
      # @param format [Symbol] The output format (`:adoc` or `:yaml`).
      # @return [String] The rendered output.
      # @raise [ArgumentError] if the format is unsupported.
      def render_reference format = :adoc
        template = case format
                   when :adoc
                     'config-reference.adoc.liquid'
                   when :yaml
                     'sample-config.yaml.liquid'
                   else
                     raise ArgumentError, "Unsupported format: #{format}"
                   end

        render_template(template)
      end

      private

      # Render a template using the Liquid engine.
      def render_template template_name
        template_path = find_template(template_name)
        raise "Template not found: #{template_name}" unless template_path

        require 'liquid'
        template_content = File.read(template_path)
        template = Liquid::Template.parse(template_content)

        template.render(
          'config_def' => @schema,
          'attrs' => @attributes)
      end

      # Find a template file in the configured template paths.
      def find_template name
        template_paths.each do |path|
          file = File.join(path, name)
          return file if File.exist?(file)
        end
        nil
      end

      # Provides an extension point for subclasses to add more template paths.
      def additional_template_paths
        # Can be overridden by subclasses
        []
      end
    end
  end
end
