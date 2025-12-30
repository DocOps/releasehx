# frozen_string_literal: true

module ReleaseHx
  module RHYML
    class Loader
      require 'yaml'
      require 'json'

      def self.load_file path
        ext = File.extname(path)
        case ext
        when '.yml', '.yaml'
          SchemaGraphy::Loader.load_yaml_with_tags(path)
        when '.json'
          JSON.parse(File.read(path))
        else
          raise "Unsupported format: #{ext}"
        end
      end
    end

    class MappingLoader < Loader
    end

    class ReleaseLoader < Loader
      def self.load path
        hash = load_file(path)
        Release.new(
          code: hash['code'],
          date: hash['date'],
          hash: hash['hash'],
          memo: hash['memo'],
          changes: hash['changes'] || hash['work'] || [])
      end
    end
  end
end
