# frozen_string_literal: true

require_relative '../../docopslab/mcp/resource_pack'
require_relative 'manifest'

module ReleaseHx
  module MCP
    # Resolves MCP resources from a YAML manifest and packaged assets.
    class ResourcePack < DocOpsLab::MCP::ResourcePack
      def initialize manifest: Manifest.load, asset_root: default_asset_root
        super
      end

      def reference_json_path
        resource = find('releasehx://config/reference.json')
        resource&.path
      end

      private

      def default_asset_root
        File.expand_path('assets', __dir__)
      end
    end
  end
end
