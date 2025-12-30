# frozen_string_literal: true

require 'yaml'
require 'psych'
require_relative 'attribute_resolver'

module SchemaGraphy
  # The Loader class provides methods for loading YAML files while preserving
  # custom tags and resolving attribute references.
  class Loader
    # Load a YAML file and resolve AsciiDoc attribute references like `\{attribute_name}`.
    #
    # @param path [String] The path to the YAML file.
    # @param attrs [Hash] The AsciiDoc attributes to use for resolution.
    # @return [Hash] The loaded YAML data with attributes resolved.
    def self.load_yaml_with_attributes path, attrs = {}
      raw_data = load_yaml_with_tags(path)
      AttributeResolver.resolve_attributes!(raw_data, attrs)
      raw_data
    end

    # Load a YAML file, preserving any custom tags (e.g., `!foo`).
    # Custom tags are attached to the data structure.
    #
    # @param path [String] The path to the YAML file.
    # @return [Hash] The loaded YAML data with custom tags attached.
    def self.load_yaml_with_tags path
      return {} if File.empty?(path)

      data = Psych.load_file(path, aliases: true, permitted_classes: [Date, Time])
      ast  = Psych.parse_file(path)
      attach_tags(ast.root, data)
      data
    end

    # Recursively attach YAML tags to the loaded data structure for template processing.
    #
    # @param node [Psych::Nodes::Node] The current AST node.
    # @param data [Object] The data corresponding to the current node.
    # @api private
    def self.attach_tags node, data
      return unless node.is_a?(Psych::Nodes::Mapping)

      node.children.each_slice(2) do |key_node, val_node|
        key = key_node.value

        if val_node.respond_to?(:tag) && val_node.tag && data[key].is_a?(String)
          normalized_tag = val_node.tag.sub(/^!+/, '').sub(/^.*:/, '')
          data[key] = {
            'value' => data[key],
            '__tag__' => normalized_tag
          }
        elsif data[key].is_a?(Hash)
          attach_tags(val_node, data[key])
        end
      end
    end
  end
end
