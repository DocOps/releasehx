# frozen_string_literal: true

require 'tilt'
require_relative '../sourcerer/templating'

# frozen_string_literal: true

module SchemaGraphy
  # A module for handling templated fields within a data structure based on a schema or definition.
  # It provides methods for pre-compiling and rendering fields using various template engines.
  module Templating
    extend Sourcerer::Templating

    # Renders a field if it is a template.
    #
    # @param field [Object] The field to render.
    # @param context [Hash] The context to use for rendering.
    # @return [Object] The rendered field, or the original field if it's not a template.
    def self.resolve_field field, context = {}
      render_field_if_template(field, context)
    end

    # Recursively pre-compiles templated fields in a data structure based on a schema.
    #
    # @param data [Hash] The data to process.
    # @param schema [Hash] The schema defining which fields are templated.
    # @param base_path [String] The base path for the current data level.
    # @param scope [Hash] The scope to use for compilation.
    def self.precompile_from_schema! data, schema, base_path = '', scope: {}
      return unless data.is_a?(Hash)

      data.each do |key, value|
        path = [base_path, key].reject(&:empty?).join('.')

        precompile_from_schema!(value, schema, path, scope: scope) if value.is_a?(Hash)

        next unless SchemaGraphy::SchemaUtils.templated_field?(schema, path)

        compile_templated_fields!(
          data: data,
          schema: schema,
          fields: [{ key: key, path: path }],
          scope: scope)
      end
    end

    # An alias for the `Sourcerer::Templating::TemplatedField` class.
    TemplatedField = Sourcerer::Templating::TemplatedField

    # Compiles templated fields in the data.
    #
    # @param data [Hash] The data containing the fields to compile.
    # @param schema [Hash] The schema definition.
    # @param fields [Array<Hash>] An array of fields to compile, each with a `:key` and `:path`.
    # @param scope [Hash] The scope to use for compilation.
    def self.compile_templated_fields! data:, schema:, fields:, scope: {}
      fields.each do |entry|
        key  = entry[:key]
        path = entry[:path]
        val  = data[key]

        next unless val.is_a?(String) || (val.is_a?(Hash) && val['__tag__'] && val['value'])

        raw     = val.is_a?(Hash) ? val['value'] : val
        tagged  = val.is_a?(Hash)
        config  = SchemaGraphy::SchemaUtils.templating_config_for(schema, path)
        engine  = tagged ? val['__tag__'] : (config['default'] || 'liquid')

        compiled = Sourcerer::Templating::Engines.compile(raw, engine)

        data[key] = if config['delay']
                      Sourcerer::Templating::TemplatedField.new(raw, compiled, engine, tagged, inferred: !tagged)
                    else
                      Sourcerer::Templating::Engines.render(compiled, engine, scope)
                    end
      end
    end

    # Recursively renders all pre-compiled templated fields in a data structure.
    #
    # @param data [Hash, Array] The data structure to process.
    # @param context [Hash] The context to use for rendering.
    def self.render_all_templated_fields! data, context = {}
      return unless data.is_a?(Hash)

      data.each do |key, value|
        case value
        when TemplatedField
          data[key] = value.render(context)
        when Hash
          render_all_templated_fields!(value, context)
        when Array
          value.each_with_index do |item, idx|
            if item.is_a?(TemplatedField)
              value[idx] = item.render(context)
            elsif item.is_a?(Hash)
              render_all_templated_fields!(item, context)
            end
          end
        end
      end
    end
  end
end
