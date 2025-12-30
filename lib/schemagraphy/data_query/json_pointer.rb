# frozen_string_literal: true

module SchemaGraphy
  module DataQuery
    # Resolves JSON Pointer queries against a Hash or Array.
    module JSONPointer
      module_function

      def resolve data, pointer
        return data if pointer.nil? || pointer == ''
        raise ArgumentError, "Invalid JSON Pointer: #{pointer}" unless pointer.start_with?('/')

        tokens = pointer.split('/')[1..]
        tokens.reduce(data) do |current, token|
          key = unescape(token)
          resolve_token(current, key, pointer)
        end
      end

      def resolve_token current, key, pointer
        case current
        when Array
          index = Integer(key, 10)
          current.fetch(index)
        when Hash
          return current.fetch(key) if current.key?(key)
          return current.fetch(key.to_sym) if current.key?(key.to_sym)

          raise KeyError, "JSON Pointer not found: #{pointer}"
        else
          raise KeyError, "JSON Pointer not found: #{pointer}"
        end
      rescue ArgumentError, IndexError, KeyError
        raise KeyError, "JSON Pointer not found: #{pointer}"
      end

      def unescape token
        token.gsub('~1', '/').gsub('~0', '~')
      end
    end
  end
end
