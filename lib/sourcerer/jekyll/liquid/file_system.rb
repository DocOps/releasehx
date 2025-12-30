# frozen_string_literal: true

require 'liquid'

module Sourcerer
  module Jekyll
    module Liquid
      # A custom Liquid file system that extends `Liquid::LocalFileSystem` to support
      # multiple root paths for template lookups. This allows templates to be
      # resolved from a prioritized list of directories.
      class FileSystem < ::Liquid::LocalFileSystem
        # Initializes the file system with one or more root paths.
        #
        # @param roots_or_root [String, Array<String>] A single root path or an array of root paths.
        # rubocop:disable Lint/MissingSuper
        # Intentional: Custom implementation that doesn't need parent's initialization
        def initialize roots_or_root
          if roots_or_root.is_a?(Array)
            @roots = roots_or_root.map { |root| File.expand_path(root) }
            @multi_root = true
          else
            @root = File.expand_path(roots_or_root)
            @multi_root = false
          end
        end
        # rubocop:enable Lint/MissingSuper

        # Finds the full path of a template, searching through multiple roots if configured.
        #
        # @param template_path [String] The path to the template.
        # @return [String] The full, validated path to the template.
        # @raise [Liquid::FileSystemError] if the template is not found.
        def full_path template_path
          if @multi_root
            @roots.each do |root|
              full = File.expand_path(File.join(root, template_path))
              return full if File.exist?(full) && full.start_with?(root)
            end
            raise ::Liquid::FileSystemError, "Template not found: '#{template_path}' in paths: #{@roots}"
          else
            full = File.expand_path(File.join(@root, template_path))
            validate_path(full)
          end
        end

        # Reads the content of a template file.
        #
        # @param template_path [String] The path to the template.
        # @return [String] The content of the template file.
        def read_template_file template_path
          path = full_path(template_path)
          File.read(path)
        end

        private

        # Validates that the resolved path is within the allowed root(s).
        def validate_path path
          if @multi_root
            # Check if path starts with any of the allowed roots
            unless @roots.any? { |root| path.start_with?(root) }
              raise ::Liquid::FileSystemError, "Illegal template path '#{path}'"
            end

          else
            raise ::Liquid::FileSystemError, "Illegal template path '#{path}'" unless path.start_with?(@root)

          end
          path
        end
      end
    end
  end
end
