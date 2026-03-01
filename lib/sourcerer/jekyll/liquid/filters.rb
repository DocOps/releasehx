# frozen_string_literal: true

require 'kramdown-asciidoc'
require 'base64'
require 'cgi'

module Sourcerer
  module Jekyll
    module Liquid
      # This module provides a set of custom filters for use in Liquid templates.
      module Filters
        # Renders a Liquid template string with a given scope.
        # @param input [String, Object] The Liquid template string or a pre-parsed template object.
        # @param vars [Hash] A hash of variables to use as the scope.
        # @return [String] The rendered output.
        def render input, vars = nil
          scope = if vars.is_a?(Hash)
                    vars.transform_keys(&:to_s)
                  else
                    {}
                  end

          template =
            if input.respond_to?(:render) && input.respond_to?(:templated?) && input.templated?
              input
            else
              ::Liquid::Template.parse(input.to_s)
            end

          template.render(scope)
        end

        # Converts a string into a slug.
        # @param input [String] The string to convert.
        # @param format [String] The desired format (`kebab`, `snake`, `camel`, `pascal`).
        # @return [String] The sluggerized string.
        def sluggerize input, format = 'kebab'
          return input unless input.is_a? String

          case format
          when 'kebab' then input.downcase.gsub(/[\s\-_]/, '-')
          when 'snake' then input.downcase.gsub(/[\s\-_]/, '_')
          when 'camel' then input.downcase.gsub(/[\s\-_]/, '_').camelize(:lower)
          when 'pascal' then input.downcase.gsub(/[\s\-_]/, '_').camelize(:upper)
          else input
          end
        end

        # Replaces double newlines with a newline and a plus sign.
        # @param input [String] The input string.
        # @return [String] The processed string.
        def plusify input
          input.gsub(/\n\n+/, "\n+\n")
        end

        # Converts a Markdown string to AsciiDoc.
        # @param input [String] The Markdown string.
        # @param wrap [String] The wrapping option for the converter.
        # @return [String] The converted AsciiDoc string.
        def md_to_adoc input, wrap = 'ventilate'
          options = {}
          options[:wrap] = wrap.to_sym if wrap
          Kramdoc.convert(input, options)
        end

        # Indents a string by a given number of spaces.
        # @param input [String] The string to indent.
        # @param spaces [Integer] The number of spaces for indentation.
        # @param line1 [Boolean] Whether to indent the first line.
        # @return [String] The indented string.
        def indent input, spaces = 2, line1: false
          indent = ' ' * spaces
          lines = input.split("\n")
          indented = if line1
                       lines.map { |line| indent + line }
                     else
                       lines.map.with_index { |line, i| i.zero? ? line : indent + line }
                     end
          indented.join("\n")
        end

        # Checks the type of a value in the context of SG-YML.
        # @param input [Object] The value to check.
        # @return [String] A string representing the type.
        def sgyml_type_check input
          if input.nil?
            'Null:nil'
          elsif input.is_a? Array
            # if all items in Array are (integer, float, string, boolean)
            if input.all? do |item|
              item.is_a?(Integer) || item.is_a?(Float) || item.is_a?(String) ||
              item.is_a?(TrueClass) || item.is_a?(FalseClass)
            end
              'Compound:ArrayList'
            elsif input.all? { |item| item.is_a?(Hash) && (item.keys.length >= 2) }
              'Compound:ArrayTable'
            else
              'Compound:Array'
            end
          elsif input.is_a? Hash
            if input.values.all? { |value| value.is_a?(Hash) && (value.keys.length >= 2) }
              'Compound:MapTable'
            else
              'Compound:Map'
            end
          elsif input.is_a? String
            'Scalar:String'
          elsif input.is_a? Integer
            'Scalar:Number'
          elsif input.is_a? Time
            'Scalar:DateTime'
          elsif input.is_a? Float
            'Scalar:Float'
          elsif input.is_a?(TrueClass) || input.is_a?(FalseClass)
            'Scalar:Boolean'
          else
            'unknown:unknown'
          end
        end

        # Returns the Ruby class name of a value.
        # @param input [Object] The value.
        # @return [String] The class name.
        def ruby_class input
          input.class.name
        end

        # Returns a string with the first letter of each word capitalized
        # @param input [String] The string to capitalize.
        # @param hyphen [Boolean] Whether to also capitalize after hyphens
        # @return [String] The capitalized string.
        # @note Does not force lowercase letters in any word
        # Example:
        #   {{ "hello world-example" | title_caps: true }}
        #   => "Hello World-Example"
        #   {{ "hello world-example" | title_caps }}
        #   => "Hello World-example"
        #   {{ "API documentation" | title_caps }}
        #   => "API Documentation"
        def title_caps input, hyphen=false
          return input unless input.is_a? String

          if hyphen
            input.gsub(/(^|[\s-])([[:alpha:]])/) { "#{::Regexp.last_match(1)}#{::Regexp.last_match(2).upcase}" }
          else
            input.gsub(/(^|\s)([[:alpha:]])/) { "#{::Regexp.last_match(1)}#{::Regexp.last_match(2).upcase}" }
          end
        end

        # Removes markup from a string.
        # @param input [String] The string to demarkupify.
        # @return [String] The demarkupified string.
        def demarkupify input
          return input unless input.is_a? String

          input = input.gsub(/`"|"`/, '"')
          input = input.gsub(/'`|`'/, "'")
          input = input.gsub(/[*_`]/, '')
          # change curly quotes to striaght quotes
          input = input.gsub(/[“”]/, '"')
          input.gsub(/[‘’]/, "'")
        end

        # Dumps a value to YAML format.
        # @param input [Object] The value to dump.
        # @return [String] The YAML representation.
        def inspect_yaml input
          require 'yaml'
          YAML.dump(input)
        end

        # Base64 encodes a string.
        # @param input [String] The string to encode.
        # @return [String] The Base64-encoded string.
        def base64 input
          return input unless input.is_a? String

          Base64.strict_encode64(input)
        end

        # Decodes a Base64-encoded string.
        # @param input [String] The string to decode.
        # @return [String] The decoded string.
        def base64_decode input
          return input unless input.is_a? String

          Base64.strict_decode64(input)
        rescue ArgumentError
          # Return original input if decoding fails
          input
        end

        # URL-encodes a string.
        # @param input [String] The string to encode.
        # @return [String] The URL-encoded string.
        def url_encode input
          return input unless input.is_a? String

          CGI.escape(input)
        end

        # Decodes a URL-encoded string.
        # @param input [String] The string to decode.
        # @return [String] The decoded string.
        def url_decode input
          return input unless input.is_a? String

          CGI.unescape(input)
        rescue ArgumentError
          # Return original input if decoding fails
          input
        end

        # HTML-escapes a string.
        # @param input [String] The string to escape.
        # @return [String] The HTML-escaped string.
        def html_escape input
          return input unless input.is_a? String

          CGI.escapeHTML(input)
        end

        # Unescapes an HTML-escaped string.
        # @param input [String] The string to unescape.
        # @return [String] The unescaped string.
        def html_unescape input
          return input unless input.is_a? String

          CGI.unescapeHTML(input)
        end
      end
    end
  end
end

# Register the filters automatically
Liquid::Template.register_filter(Sourcerer::Jekyll::Liquid::Filters)
