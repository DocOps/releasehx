# frozen_string_literal: true

module SchemaGraphy
  # A utility module for working with the custom tag data structure.
  # The structure is a hash with 'value' and '__tag__' keys.
  module TagUtils
    # Extracts the original value from a tagged data structure.
    #
    # @param value [Object] The tagged value (a Hash) or any other value.
    # @return [Object] The original value, or the value itself if not tagged.
    def self.detag value
      value.is_a?(Hash) && value.key?('value') ? value['value'] : value
    end

    # Retrieves the tag from a tagged data structure.
    #
    # @param value [Object] The tagged value (a Hash) or any other value.
    # @return [String, nil] The tag string, or `nil` if not tagged.
    def self.tag_of value
      value.is_a?(Hash) ? value['__tag__'] : nil
    end

    # Checks if a value has a specific tag.
    #
    # @param value [Object] The tagged value to check.
    # @param tag [String, Symbol] The tag to check for.
    # @return [Boolean] `true` if the value has the specified tag, `false` otherwise.
    def self.tag? value, tag
      tag_of(value)&.to_s == tag.to_s
    end
  end
end
