# frozen_string_literal: true

module DocOpsLab
  module MCP
    # Resolves MCP resources from a YAML manifest and packaged assets.
    class ResourcePack
      Resource = Struct.new(:uri, :name, :description, :mime_type, :path, keyword_init: true)

      def initialize manifest:, asset_root:
        raise ArgumentError, 'asset_root is required' if asset_root.nil? || asset_root == ''

        @manifest = manifest
        @asset_root = asset_root
      end

      def resources
        @manifest.resources.map do |entry|
          normalized = @manifest.normalize_resource(entry)
          Resource.new(
            uri: normalized[:uri],
            name: normalized[:name],
            description: normalized[:description],
            mime_type: normalized[:mime_type],
            path: File.join(@asset_root, normalized[:packaged_name]))
        end
      end

      def list
        resources.map(&:uri)
      end

      def find uri
        resources.find { |entry| entry.uri == uri }
      end

      def read uri
        resource = find(uri)
        raise ArgumentError, "Unknown MCP resource: #{uri}" unless resource

        raise Errno::ENOENT, "Missing MCP resource file: #{resource.path}" unless File.exist?(resource.path)

        File.read(resource.path)
      end
    end
  end
end
