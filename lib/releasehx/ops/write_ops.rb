# frozen_string_literal: true

require 'fileutils'
require 'tilt'
require_relative 'template_ops'

module ReleaseHx
  # Provides file writing operations and template processing utilities for output generation.
  #
  # The WriteOps module handles safe file creation with directory management, template resolution
  # with user/gem fallback paths, and content post-processing for consistent output formatting.
  module WriteOps
    # Safely writes content to a file, creating parent directories as needed.
    #
    # Ensures parent directory structure exists before writing and provides
    #  logging feedback for successful file creation operations.
    #
    # @param path [String] The target file path for writing.
    # @param content [String] The content to write to the file.
    # @return [Symbol] Returns :written to indicate successful completion.
    def self.safe_write path, content
      dirname = File.dirname(path)
      FileUtils.mkdir_p(dirname)
      File.write(path, content)
      ReleaseHx.logger.info "Wrote file: #{path}"
      :written
    end

    # Establishes the absolute path to the gem's bundled template directory.
    #
    # @return [String] The path to the default gem template directory.
    def self.gem_template_root
      File.expand_path('../rhyml/templates', __dir__)
    end

    # Resolves template file path using hierarchical search with user directory precedence.
    #
    # Searches for templates first in user-configured directories, then falls back to
    #  gem-bundled templates, providing clear error messages when templates are not found.
    #
    # @param name [String] The template filename to locate.
    # @param config [ReleaseHx::Configuration] Configuration object containing template path settings.
    # @return [String] The absolute path to the located template file.
    # @raise [StandardError] If the template cannot be found in any search path.
    def self.resolve_template_path name, config
      user_dir = config.dig('paths', 'templates_dir')
      fallback_dir = gem_template_root

      search_paths = []
      search_paths << File.expand_path(name, user_dir) if user_dir
      search_paths << File.join(fallback_dir, name)

      found = search_paths.find { |p| File.exist?(p) }

      return found if found

      raise "Template not found: #{name} (searched #{search_paths.join(' , ')})"
    end

    # Processes a Liquid template file with variable substitution and content post-processing.
    #
    # Loads and renders templates using the TemplateOps system, then applies configurable
    # post-processing rules such as excess line removal for consistent output formatting.
    #
    # @param template_path [String] The absolute path to the template file.
    # @param vars [Hash] Variable context for template rendering.
    # @param config [ReleaseHx::Configuration] Configuration object with processing settings.
    # @return [String] The fully processed template output.
    def self.process_template template_path, vars, config
      template_content = File.read(template_path)
      includes_load_paths = []
      user_templates_dir = config.dig('paths', 'templates_dir')
      gem_templates_dir  = File.expand_path('../../rhyml/templates', __dir__)

      if user_templates_dir
        unless Pathname.new(user_templates_dir).absolute?
          user_templates_dir = File.expand_path(user_templates_dir, Dir.pwd)
        end
        includes_load_paths << user_templates_dir
      end

      includes_load_paths << gem_templates_dir

      rendered = TemplateOps.render_liquid_string(template_content, vars, config)

      # Apply configurable post-processing for line spacing control
      blank_lines = config.dig('modes', 'remove_excess_lines')
      if blank_lines.zero?
        rendered = rendered.gsub(/\n{2,}/, "\n")
      elsif blank_lines
        rendered = rendered.gsub(/\n{#{blank_lines + 1},}/, "\n" * (blank_lines + 1))
      end

      rendered
    end

    # Appends new changes to an existing YAML file using template-based formatting.
    #
    # Generates properly formatted YAML content for new changes using a template,
    #  then appends it to the specified file while maintaining file structure.
    #
    # @param yaml_file_path [String] The path to the target YAML file for appending.
    # @param new_changes [Array<ReleaseHx::RHYML::Change>] Array of Change objects to append.
    # @param config [ReleaseHx::Configuration] Configuration object for template processing.
    # @return [void]
    def self.append_changes_to_yaml yaml_file_path, new_changes, config
      # Generate properly formatted YAML content using template
      context = {
        'changes' => new_changes.map(&:to_h),
        'config' => config
      }

      template_path = resolve_template_path('rhyml-change-append.yaml.liquid', config)
      append_content = process_template(template_path, { 'vars' => context }, config)

      # Append to existing file maintaining structure
      File.open(yaml_file_path, 'a') do |file|
        file.write(append_content)
      end

      ReleaseHx.logger.debug "Appended #{new_changes.size} changes to #{yaml_file_path}"
    end
  end
end
