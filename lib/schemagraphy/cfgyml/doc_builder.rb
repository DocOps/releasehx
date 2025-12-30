# frozen_string_literal: true

require 'json'

module SchemaGraphy
  module CFGYML
    # Builds documentation-friendly CFGYML references for machine consumption.
    module DocBuilder
      module_function

      def call schema, options = {}
        pretty = options.fetch(:pretty, true)
        data = reference_hash(schema)
        pretty ? JSON.pretty_generate(data) : JSON.generate(data)
      end

      def reference_hash schema
        {
          'format' => 'releasehx-config-reference',
          'version' => 1,
          'properties' => build_properties(schema['properties'], [])
        }
      end

      def build_properties properties, path
        return {} unless properties.is_a?(Hash)

        properties.each_with_object({}) do |(key, definition), acc|
          next unless definition.is_a?(Hash)

          current_path = path + [key]
          entry = build_entry(current_path, definition)
          children = build_properties(definition['properties'], current_path)
          entry['properties'] = children unless children.empty?
          acc[key] = entry
        end
      end

      def build_entry path, definition
        entry = {
          'path' => path.join('.'),
          'desc' => definition['desc'],
          'docs' => definition['docs'],
          'type' => definition['type'],
          'templating' => definition['templating'],
          'default' => definition.key?('dflt') ? definition['dflt'] : nil
        }
        entry.compact
      end
    end
  end
end
