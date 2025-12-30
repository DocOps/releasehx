# frozen_string_literal: true

require 'liquid'

module Sourcerer
  # This module provides the core templating functionality for Sourcerer.
  # It includes modules for template engines, and classes for representing
  # templated fields and their context.
  module Templating
    # This module handles the compilation and rendering of templates.
    module Engines
      module_function

      # A hash of supported template engines.
      SUPPORTED_ENGINES = {
        'liquid' => 'liquid',
        'erb'    => 'erb'
      }.freeze

      # Compiles a template string using the specified engine.
      #
      # @param str [String] The template string to compile.
      # @param engine [String] The name of the template engine to use.
      # @return [Object] The compiled template object.
      # @raise [ArgumentError] if the engine is not supported.
      def compile str, engine
        case engine.to_s
        when 'liquid'
          Liquid::Template.parse(str)
        when 'erb'
          require 'erb'
          ERB.new(str)
        else
          raise ArgumentError, "Unsupported engine: #{engine}"
        end
      end

      # Renders a compiled template with the given variables.
      #
      # @param compiled [Object] The compiled template object.
      # @param engine [String] The name of the template engine.
      # @param vars [Hash] A hash of variables to use for rendering.
      # @return [String] The rendered output.
      def render compiled, engine, vars = {}
        case engine.to_s
        when 'liquid'
          compiled.render(vars)
        when 'erb'
          compiled.result_with_hash(vars)
        else
          compiled.to_s
        end
      end
    end

    # Represents a field that will be rendered by a template engine.
    class TemplatedField
      # @return [String] The raw, un-rendered template string.
      attr_reader :raw
      # @return [Object] The compiled template object.
      attr_reader :compiled
      # @return [String] The name of the template engine.
      attr_reader :engine
      # @return [Boolean] Whether the template was explicitly tagged.
      attr_reader :tagged
      # @return [Boolean] Whether the template engine was inferred.
      attr_reader :inferred

      # @param raw [String] The raw template string.
      # @param compiled [Object] The compiled template object.
      # @param engine [String] The name of the template engine.
      # @param tagged [Boolean] Whether the template was explicitly tagged.
      # @param inferred [Boolean] Whether the template engine was inferred.
      def initialize raw, compiled, engine, tagged, inferred
        @raw      = raw
        @compiled = compiled
        @engine   = engine
        @tagged   = tagged
        @inferred = inferred
      end

      # @return [true] Always returns true to indicate this is a templated field.
      def templated?
        true
      end

      # @return [Boolean] True if the field is deferred (not yet compiled).
      def deferred?
        compiled.nil?
      end

      # @return [self] Returns self for Liquid compatibility.
      def to_liquid
        self
      end

      # Renders the template with the given context.
      # @param context [Hash, Liquid::Context] The context for rendering.
      # @return [String] The rendered output.
      def render context = {}
        scope = context.respond_to?(:environments) ? context.environments.first : context
        Engines.render(compiled, engine, scope)
      end

      # Renders the template with an empty context.
      # @return [String] The rendered output.
      def to_s
        render({})
      end
    end

    # Holds contextual information for templating.
    class Context
      # @return [Symbol] The rendering stage (e.g., `:load`).
      attr_reader :stage
      # @return [Boolean] Whether to use strict rendering.
      attr_reader :strict
      # @return [Hash] A hash of scopes for rendering.
      attr_reader :scopes

      # @param stage [Symbol] The rendering stage.
      # @param strict [Boolean] Whether to use strict rendering.
      # @param scopes [Hash] A hash of scopes.
      def initialize stage: :load, strict: false, scopes: {}
        @stage  = stage.to_sym
        @strict = strict
        @scopes = scopes.transform_keys(&:to_sym)
      end

      # Creates a new Context object from a schema fragment.
      # @param schema_fragment [Hash] The schema fragment containing templating info.
      # @return [Context] The new Context object.
      def self.from_schema schema_fragment
        render_conf = schema_fragment['templating'] || {}

        stage  = (render_conf['stage'] || :load).to_sym
        strict = render_conf['strict'] == true
        scopes = (render_conf['scopes'] || {}).transform_keys(&:to_sym)

        new(stage: stage, strict: strict, scopes: scopes)
      end

      # Merges all scopes into a single hash.
      # @return [Hash] The merged scope.
      def merged_scope
        scopes.values.reduce({}) { |acc, s| acc.merge(s) }
      end
    end

    # Compiles templated fields in a data structure.
    # @param data [Hash] The data to process.
    # @param schema [Hash] The schema defining the fields.
    # @param fields [Array<Hash>] The fields to compile.
    # @param scope [Hash] The scope for rendering.
    def self.compile_templated_fields! data:, schema:, fields:, scope: {}
      fields.each do |field_entry|
        key  = field_entry[:key]
        path = field_entry[:path]
        val  = data[key]

        next unless val.is_a?(String) || (val.is_a?(Hash) && val['__tag__'] && val['value'])

        raw     = val.is_a?(Hash) ? val['value'] : val
        tagged  = val.is_a?(Hash)
        config  = SchemaGraphy::SchemaUtils.templating_config_for(schema, path)
        engine  = tagged ? val['__tag__'] : (config['default'] || 'liquid')

        compiled = Engines.compile(raw, engine)

        data[key] = if config['delay']
                      TemplatedField.new(raw, compiled, engine, tagged, inferred: !tagged)
                    else
                      Engines.render(compiled, engine, scope)
                    end
      end
    end

    # Renders a field if it is a template.
    # @param val [Object] The value to render.
    # @param context [Hash] The context for rendering.
    # @return [Object] The rendered value, or the original value if not a template.
    def self.render_field_if_template val, context = {}
      if val.respond_to?(:templated?) && val.templated?
        val.render(context)
      else
        val
      end
    end
  end
end
