# frozen_string_literal: true

require 'yaml'

module DocOpsLab
  module MCP
    # Loads MCP resource and tool definitions from a YAML manifest.
    class Manifest
      def initialize data
        @data = data
      end

      def self.load path
        raise ArgumentError, 'Manifest path is required' if path.nil? || path == ''

        new(YAML.safe_load_file(path, symbolize_names: true, aliases: true))
      end

      def resources
        Array(@data[:resources])
      end

      def tools
        Array(@data[:tools])
      end

      def normalize_resource entry
        {
          uri: entry[:href],
          name: entry[:name],
          description: entry[:desc],
          mime_type: entry[:mime],
          source_path: entry[:path],
          packaged_name: entry[:file]
        }
      end

      def normalize_tool entry
        {
          name: entry[:name],
          # Convert dots to spaces, capitalize initials
          title: entry[:title] || entry[:name].tr('.', ' ').split.map(&:capitalize).join(' '),
          description: entry[:desc],
          input_schema: normalize_schema(entry[:input_schema]),
          annotations: entry[:annotations]
        }
      end

      private

      # Recursively normalize schema keys (ex: :desc to :description)
      def normalize_schema value
        case value
        when Hash
          value.each_with_object({}) do |(key, inner), acc|
            mapped_key = key == :desc ? :description : key
            acc[mapped_key] = normalize_schema(inner)
          end
        when Array
          value.map { |item| normalize_schema(item) }
        else
          value
        end
      end
    end
  end
end
