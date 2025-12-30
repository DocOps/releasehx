# frozen_string_literal: true

require_relative '../../docopslab/mcp/asset_packager'
require_relative 'manifest'

module ReleaseHx
  module MCP
    # Copies MCP resource assets into a packaged location for runtime access.
    class AssetPackager < DocOpsLab::MCP::AssetPackager
      def initialize manifest: Manifest.load, asset_root: default_asset_root
        super
      end

      private

      def default_asset_root
        File.expand_path('assets', __dir__)
      end
    end
  end
end
