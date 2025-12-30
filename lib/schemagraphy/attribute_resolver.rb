# frozen_string_literal: true

module SchemaGraphy
  # The AttributeResolver module provides methods for resolving AsciiDoc attribute references
  # within a schema hash. It is used to substitute placeholders like `\{attribute_name}`
  # with actual values.
  module AttributeResolver
    # Recursively walk a schema Hash and resolve `\{attribute_name}` references
    # in 'dflt' values.
    #
    # @param schema [Hash] The schema or definition hash to process.
    # @param attrs [Hash] The key-value pairs from AsciiDoc attributes to use for resolution.
    # @return [Hash] The schema with resolved attributes.
    def self.resolve_attributes! schema, attrs
      case schema
      when Hash
        schema.transform_values! do |value|
          if value.is_a?(Hash)
            if value.key?('dflt') && value['dflt'].is_a?(String)
              value['dflt'] = resolve_attribute_reference(value['dflt'], attrs)
            end
            resolve_attributes!(value, attrs)
          else
            value
          end
        end
      end
      schema
    end

    # Replace `\{attribute_name}` patterns with corresponding values from the attrs hash.
    #
    # @param value [String] The string to process.
    # @param attrs [Hash] The attributes to use for resolution.
    # @return [String] The processed string with attribute references replaced.
    def self.resolve_attribute_reference value, attrs
      # Handle \{attribute_name} references
      if value.match?(/\{[^}]+\}/)
        value.gsub(/\{([^}]+)\}/) do |match|
          attr_name = ::Regexp.last_match(1)
          attrs[attr_name] || match # Keep original if no matching attribute
        end
      else
        value
      end
    end
  end
end
