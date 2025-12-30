# frozen_string_literal: true

require 'mcp'

module DocOpsLab
  module MCP
    # Hosts MCP resources and tools from a manifest-driven resource pack.
    class Server
      def initialize name:, manifest:, resource_pack:, tool_handler: nil
        raise ArgumentError, 'name is required' if name.nil? || name == ''

        @manifest = manifest
        @resource_pack = resource_pack
        @tool_handler = tool_handler
        @server = ::MCP::Server.new(
          name: name,
          resources: mcp_resources,
          tools: mcp_tools)

        register_resource_reader
      end

      def start_stdio
        transport = ::MCP::Server::Transports::StdioTransport.new(@server)
        transport.open
      end

      def list_resources
        @resource_pack.list
      end

      def get_resource uri
        @resource_pack.read(uri)
      end

      private

      def register_resource_reader
        @server.resources_read_handler do |params|
          uri = params[:uri]
          resource = @resource_pack.find(uri)
          raise ArgumentError, "Unknown MCP resource: #{uri}" unless resource

          [{
            uri:,
            mimeType: resource.mime_type,
            text: @resource_pack.read(uri)
          }]
        end
      end

      def mcp_resources
        @resource_pack.resources.map do |entry|
          ::MCP::Resource.new(
            uri: entry.uri,
            name: entry.name,
            title: entry.name,
            description: entry.description,
            mime_type: entry.mime_type)
        end
      end

      def mcp_tools
        @manifest.tools.map do |tool|
          normalized = @manifest.normalize_tool(tool)
          build_tool(normalized)
        end
      end

      def build_tool tool
        tool_handler = @tool_handler
        ::MCP::Tool.define(
          name: tool[:name],
          title: tool[:title],
          description: tool[:description],
          input_schema: tool[:input_schema],
          annotations: tool[:annotations]) do |**args|
          server_context = args.delete(:server_context)
          raise ArgumentError, "No MCP tool handler configured for: #{tool[:name]}" unless tool_handler

          tool_handler.call(tool[:name], args, server_context)
        end
      end

      def handle_tool name, args, server_context
        raise ArgumentError, "No MCP tool handler configured for: #{name}" unless @tool_handler

        @tool_handler.call(name, args, server_context)
      end
    end
  end
end
