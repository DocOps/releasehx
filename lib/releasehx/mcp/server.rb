# frozen_string_literal: true

require 'json'
require_relative '../../schemagraphy'
require_relative '../../docopslab/mcp/server'
require_relative 'manifest'
require_relative 'resource_pack'

module ReleaseHx
  module MCP
    # Hosts MCP resources and tools for configuration discovery.
    class Server < DocOpsLab::MCP::Server
      def initialize manifest: Manifest.load, resource_pack: nil
        @manifest = manifest
        @resource_pack = resource_pack || ResourcePack.new(manifest: @manifest)
        @reference = build_reference
        super(
          name: 'releasehx-mcp',
          manifest: @manifest,
          resource_pack: @resource_pack,
          tool_handler: method(:handle_tool))
      end

      private

      def build_reference
        json_path = @resource_pack.reference_json_path
        return nil unless json_path && File.exist?(json_path)

        SchemaGraphy::CFGYML::PathReference.load(json_path)
      end

      def handle_tool name, args, _server_context
        case name
        when 'config.reference.get'
          handle_reference_get(args)
        else
          raise ArgumentError, "Unknown MCP tool: #{name}"
        end
      end

      def handle_reference_get args
        raise ArgumentError, 'Reference JSON not available' unless @reference

        pointer = args[:pointer] || args['pointer']
        raise ArgumentError, 'Missing JSON Pointer value' if pointer.nil? || pointer == ''

        result = @reference.get(pointer)
        ::MCP::Tool::Response.new(
          [{ type: 'text', text: JSON.generate(result) }],
          structured_content: result)
      rescue KeyError => e
        ::MCP::Tool::Response.new([{ type: 'text', text: e.message }], error: true)
      end
    end
  end
end
