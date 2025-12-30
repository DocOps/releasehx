# frozen_string_literal: true

require_relative '../../docopslab/mcp/manifest'

module ReleaseHx
  module MCP
    # Loads MCP resource and tool definitions from a YAML manifest.
    class Manifest < DocOpsLab::MCP::Manifest
      def self.load path = default_path
        super
      end

      def self.default_path
        File.expand_path('../../../specs/data/mcp-manifest.yml', __dir__)
      end
    end
  end
end
