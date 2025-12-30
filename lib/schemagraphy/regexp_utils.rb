# frozen_string_literal: true

require 'to_regexp'

module SchemaGraphy
  # A utility module for robustly parsing and using regular expressions.
  # It handles various formats, including literals and plain strings,
  # and provides helpers for extracting captured content.
  module RegexpUtils
    module_function

    # Parse a regex pattern string using the `to_regexp` gem for robust parsing.
    # Handles `/pattern/flags`, `%r{pattern}flags`, and plain text formats.
    #
    # @example
    #   parse_pattern("/^hello.*$/im")
    #   # => { pattern: "^hello.*$", flags: "im", regexp: /^hello.*$/im, options: 6 }
    #
    # @example
    #   parse_pattern("hello world")
    #   # => { pattern: "hello world", flags: "", regexp: /hello world/, options: 0 }
    #
    # @example
    #   parse_pattern("hello world", "i")
    #   # => { pattern: "hello world", flags: "i", regexp: /hello world/i, options: 1 }
    #
    # @param input [String] The input string, e.g., "/pattern/flags" or "plain pattern".
    # @param default_flags [String] Default flags to apply if none are specified (default: "").
    # @return [Hash, nil] A hash with `:pattern`, `:flags`, `:regexp`, and `:options`, or `nil`.
    def parse_pattern input, default_flags = ''
      return nil if input.nil? || input.to_s.strip.empty?

      input_str = input.to_s.strip

      # Remove surrounding quotes that might come from YAML parsing
      clean_input = input_str.gsub(/^["']|["']$/, '')

      # Heuristic to detect if it's a Regexp literal
      is_literal = (clean_input.start_with?('/') && clean_input.rindex('/').positive?) || clean_input.start_with?('%r{')

      if is_literal
        # Try to parse as regex literal using to_regexp
        begin
          regexp_obj = clean_input.to_regexp(detect: true)

          # Extract pattern and flags from the compiled regexp
          pattern_str = regexp_obj.source
          flags_str = extract_flags_from_regexp(regexp_obj)

          {
            pattern: pattern_str,
            flags: flags_str,
            regexp: regexp_obj,
            options: regexp_obj.options
          }
        rescue RegexpError => e
          # Malformed literal is an error
          raise RegexpError, "Invalid regex literal '#{input}': #{e.message}"
        end
      else
        # Treat as plain pattern string with default flags
        flags_str = default_flags.to_s
        options = flags_to_options(flags_str)

        begin
          regexp_obj = Regexp.new(clean_input, options)

          {
            pattern: clean_input,
            flags: flags_str,
            regexp: regexp_obj,
            options: options
          }
        rescue RegexpError => e
          raise RegexpError, "Invalid regex pattern '#{input}': #{e.message}"
        end
      end
    end

    # @note Not yet implemented.
    # Future enhancement to parse structured pattern definitions from a Hash.
    # @param pattern_hash [Hash] A hash with 'pattern' and 'flags' keys.
    # @raise [NotImplementedError] Always raises this error.
    def parse_structured_pattern pattern_hash
      # TODO: Implement structured pattern parsing
      # pattern_hash should have 'pattern' and 'flags' keys
      # flags can be string or array
      raise NotImplementedError, 'Structured pattern parsing not yet implemented'
    end

    # @note Not yet implemented.
    # Future enhancement to parse custom YAML tags for regular expressions.
    # @param tagged_input [String] The input string with a YAML tag.
    # @param tag_type [Symbol] The type of tag, e.g., `:literal` or `:pattern`.
    # @raise [NotImplementedError] Always raises this error.
    def parse_tagged_pattern tagged_input, tag_type
      # TODO: Implement custom YAML tag parsing
      # tag_type would be :literal or :pattern
      raise NotImplementedError, 'Tagged pattern parsing not yet implemented'
    end

    # Convert a flags string (ex: "im") to a Regexp options integer.
    #
    # @param flags [String] String containing regex flags.
    # @return [Integer] Regexp options integer.
    def flags_to_options flags
      options = 0
      flags = flags.to_s

      options |= Regexp::IGNORECASE if flags.include?('i')
      options |= Regexp::MULTILINE if flags.include?('m')
      options |= Regexp::EXTENDED if flags.include?('x')

      # NOTE: 'g' (global) and 'o' (once) are not standard Ruby flags
      # encoding flags ('n', 'e', 's', 'u') are handled by to_regexp

      options
    end

    # Extract a flags string from a compiled Regexp object.
    #
    # @param regexp [Regexp] A compiled regexp object.
    # @return [String] String representation of the flags (e.g., "im").
    def extract_flags_from_regexp regexp
      flags = ''
      flags += 'i' if regexp.options.anybits?(Regexp::IGNORECASE)
      flags += 'm' if regexp.options.anybits?(Regexp::MULTILINE)
      flags += 'x' if regexp.options.anybits?(Regexp::EXTENDED)
      flags
    end

    # Create a Regexp object from a pattern string and explicit flags.
    #
    # @param pattern [String] The regex pattern (without delimiters).
    # @param flags [String] The flags string (ex: "im").
    # @return [Regexp] The compiled Regexp object.
    def create_regexp pattern, flags = ''
      options = flags_to_options(flags)
      Regexp.new(pattern, options)
    end

    # Extract content using named or positional capture groups.
    #
    # @param text [String] The text to match against.
    # @param pattern_info [Hash] The hash result from `parse_pattern`.
    # @param capture_name [String] The name of the capture group to extract (optional).
    # @return [String, nil] The extracted text, or `nil` if no match is found.
    def extract_capture text, pattern_info, capture_name = nil
      return nil unless text && pattern_info

      regexp = pattern_info[:regexp]
      match = text.match(regexp)

      return nil unless match

      if capture_name && match.names.include?(capture_name.to_s)
        # Extract named capture group
        match[capture_name.to_s]
      elsif match.captures.any?
        # Extract first capture group
        match[1]
      else
        # Return the entire match
        match[0]
      end
    end

    # Extract all named capture groups as a hash or positional captures as an array.
    #
    # @param text [String] The text to match against.
    # @param pattern_info [Hash] The hash result from `parse_pattern`.
    # @return [Hash, Array, nil] A hash of named captures, an array of positional captures, or `nil`.
    def extract_all_captures text, pattern_info
      return nil unless text && pattern_info

      regexp = pattern_info[:regexp]
      match = text.match(regexp)

      return nil unless match

      if match.names.any?
        # Return hash of named captures
        match.names.each_with_object({}) do |name, captures|
          captures[name] = match[name]
        end
      else
        # Return array of positional captures
        match.captures
      end
    end

    # A convenience method that combines parsing and a single extraction.
    #
    # @param text [String] The text to match against.
    # @param pattern_input [String] The pattern string (with or without /flags/).
    # @param capture_name [String] Name of the capture group to extract (optional).
    # @param default_flags [String] Default flags if the pattern has no flags.
    # @return [String, nil] The extracted text, or `nil` if no match is found.
    def parse_and_extract text, pattern_input, capture_name = nil, default_flags = ''
      pattern_info = parse_pattern(pattern_input, default_flags)
      extract_capture(text, pattern_info, capture_name)
    end

    # A convenience method that combines parsing and extraction of all captures.
    #
    # @param text [String] The text to match against.
    # @param pattern_input [String] The pattern string (with or without /flags/).
    # @param default_flags [String] Default flags if the pattern has no flags.
    # @return [Hash, Array, nil] All captured content, or `nil` if no match is found.
    def parse_and_extract_all text, pattern_input, default_flags = ''
      pattern_info = parse_pattern(pattern_input, default_flags)
      extract_all_captures(text, pattern_info)
    end
  end
end
