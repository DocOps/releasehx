# frozen_string_literal: true

module SchemaGraphy
  # A utility module for introspecting schema definitions.
  # Provides methods for retrieving metadata, default values, and type information
  # from a schema hash using a dot-separated path syntax.
  module SchemaUtils
    module_function

    # Retrieve a nested property definition from a schema using a dot-separated path.
    #
    # @example Schema Structure
    #   schema = {
    #     "$schema": {
    #       "properties": {
    #         "property1": {
    #           "properties": {
    #             "subproperty1": {
    #               "default": "value1",
    #               "type": "String"
    #             }
    #           }
    #         }
    #       }
    #     }
    #   }
    #   crawl_properties(schema, "property1.subproperty1")
    #   # => { "default" => "value1", "type" => "String" }
    #
    # @param schema [Hash] The schema hash to crawl.
    # @param path [String] The dot-separated path to the property.
    # @return [Hash, nil] The property definition hash, or `nil` if not found.
    def crawl_properties schema, path
      path_components = path.split('.')
      current = schema['$schema'] || schema

      path_components.each do |component|
        return nil unless current.is_a?(Hash)
        return nil unless current['properties']&.key?(component)

        current = current['properties'][component]
      end

      current
    end

    # Get the default value for a property from the schema.
    #
    # @param schema [Hash] The schema hash.
    # @param path [String] The dot-separated path to the property.
    # @return [Object, nil] The default value, or `nil` if not defined.
    def default_for schema, path
      property = crawl_properties(schema, path)
      return nil unless property.is_a?(Hash)

      property['default'] || property['dflt']
    end

    # Get the type for a property from the schema.
    #
    # @param schema [Hash] The schema hash.
    # @param path [String] The dot-separated path to the property.
    # @return [String, nil] The property type, or `nil` if not defined.
    def type_for schema, path
      property = crawl_properties(schema, path)
      return nil unless property.is_a?(Hash)

      property['type']
    end

    # Get the templating configuration for a property from the schema.
    #
    # @param schema [Hash] The schema hash.
    # @param path [String] The dot-separated path to the property.
    # @return [Hash] The templating configuration hash.
    def templating_config_for schema, path
      property = crawl_properties(schema, path)
      return {} unless property.is_a?(Hash)

      return property['templating'] if property['templating']

      if property['type'].to_s.downcase == 'liquid'
        { 'default' => 'liquid', 'delay' => true }
      elsif property['type'].to_s.downcase == 'erb'
        { 'default' => 'erb', 'delay' => true }
      else
        {}
      end
    end

    # Check if a property is a templated field.
    #
    # @param schema [Hash] The schema hash.
    # @param path [String] The dot-separated path to the property.
    # @return [Boolean] `true` if the field has templating configured, `false` otherwise.
    def templated_field? schema, path
      property = crawl_properties(schema, path)
      return false unless property.is_a?(Hash)

      property.key?('templating') && property['templating'].is_a?(Hash)
    end

    # Crawl the schema to find the metadata for a given path.
    #
    # @param schema [Hash] The schema hash.
    # @param path [String, nil] The dot-separated path.
    # @return [Hash] The metadata hash.
    def self.crawl_meta schema, path = nil
      parts = path ? path.split('.') : []
      node = schema['$schema'] || schema
      meta = {}

      parts.each do |part|
        node = node['properties'][part] if node['properties']&.key?(part)
        break unless node.is_a?(Hash)

        # Only update meta if this level has it
        meta = node if node['templating']
      end

      meta['$meta'] || meta['sgyml'] || meta['templating'] || {}
    end
  end
end
