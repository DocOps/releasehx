# frozen_string_literal: true

require 'fileutils'

module DocOpsLab
  module MCP
    # Copies MCP resource assets into a packaged location for runtime access.
    class AssetPackager
      def initialize manifest:, asset_root:
        raise ArgumentError, 'asset_root is required' if asset_root.nil? || asset_root == ''

        @manifest = manifest
        @asset_root = asset_root
      end

      def package!
        FileUtils.mkdir_p(@asset_root)
        @manifest.resources.each do |entry|
          normalized = @manifest.normalize_resource(entry)
          source_path = normalized[:source_path]
          target_path = File.join(@asset_root, normalized[:packaged_name])
          raise Errno::ENOENT, "Missing MCP resource source: #{source_path}" unless File.exist?(source_path)

          FileUtils.mkdir_p(File.dirname(target_path))
          FileUtils.cp(source_path, target_path)
        end
      end
    end
  end
end
