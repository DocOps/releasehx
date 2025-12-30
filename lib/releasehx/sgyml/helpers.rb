# frozen_string_literal: true

require_relative '../../schemagraphy/templating'

module ReleaseHx
  module SgymlHelpers
    # Precompiles a schema into a set of templates, using the provided data and schema.
    def self.precompile_from_schema! data, schema, base_path = '', scope: {}
      SchemaGraphy::Templating.precompile_from_schema!(data, schema, base_path, scope: scope)
    end

    # Renders all templated fields in a given Hash if they've previously been parsed
    def self.render_stage_fields! data, stage
      data.each do |key, value|
        next unless value.is_a?(Sourcerer::Templating::TemplatedField)

        tmpl_context = value.context
        next unless tmpl_context.respond_to?(:stage)
        next unless tmpl_context.stage.to_sym == stage.to_sym

        data[key] = value.render
      end
    end

    # Recursively converts all keys in a Hash or Array to strings,
    #  safely handling non-stringifiable objects
    def self.deep_stringify_safe obj
      case obj
      when Hash
        obj.each_with_object({}) do |(k, v), h|
          h[k.to_s] = deep_stringify_safe(v)
        end
      when Array
        obj.map { |v| deep_stringify_safe(v) }
      else
        begin
          obj.to_yaml
          obj
        rescue TypeError
          obj.to_s
        end
      end
    end
  end
end
