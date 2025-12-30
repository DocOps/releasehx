# frozen_string_literal: true

require 'json'

module SchemaGraphy
  module CFGYML
    # Loads and queries a JSON config reference using JSON Pointer.
    class PathReference
      def initialize data
        @data = data
      end

      def self.load path
        new(JSON.parse(File.read(path)))
      end

      def get pointer
        SchemaGraphy::DataQuery::JSONPointer.resolve(@data, pointer)
      end
    end

    Reference = PathReference
  end
end
