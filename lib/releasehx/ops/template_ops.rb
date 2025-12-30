# frozen_string_literal: true

require 'pathname'

module ReleaseHx
  # Provides Liquid template rendering services with extended Jekyll integration and configurable template paths.
  #
  # The TemplateOps module handles the complex setup required for Liquid template processing, including
  #  Jekyll plugin loading, template path resolution, and Sourcerer Jekyll runtime initialization for
  #  advanced template features and includes.
  module TemplateOps
    # Renders a Liquid template string with provided variables and configuration context.
    #
    # Sets up a complete, enhanced Liquid rendering environment with plugin support,
    #  configurable template include paths, and proper site context for advanced template features.
    # Supports both user-defined and gem-bundled template directories with fallback resolution.
    #
    # @param input [String] The raw Liquid template string to process.
    # @param vars [Hash] Variable context for template variable substitution.
    # @param config [ReleaseHx::Configuration] Configuration object containing template path settings.
    # @return [String] The fully rendered template output.
    # @raise [StandardError] If template rendering fails due to syntax errors or missing variables.
    def self.render_liquid_string input, vars, config
      plugin_dirs = [File.expand_path('../../../jekyll_plugins', __dir__)]
      user_templates_dir = config.dig('paths', 'templates_dir')
      gem_templates_dir  = File.expand_path('../rhyml/templates', __dir__)

      # Build template include path hierarchy: user templates take precedence over gem defaults
      includes = []
      if user_templates_dir
        unless Pathname.new(user_templates_dir).absolute?
          user_templates_dir = File.expand_path(user_templates_dir, Dir.pwd)
        end
        includes << user_templates_dir if File.directory?(user_templates_dir)
      end
      includes << gem_templates_dir

      Sourcerer::Jekyll.initialize_liquid_runtime

      # Bootstrap an ephemeral Jekyll site context for template processing with full feature support
      site = Sourcerer::Jekyll::Bootstrapper.fake_site(
        includes_load_paths: includes,
        plugin_dirs: plugin_dirs)

      # Parse template and render with comprehensive register context
      tpl = ::Liquid::Template.parse(input)
      rendered = tpl.render(
        vars,
        registers: {
          site: site,
          file_system: Sourcerer::Jekyll::Liquid::FileSystem.new(includes.first),
          includes_load_paths: includes,
          releasehx_debug: true
        })

      raise "Template rendering failed:\n#{rendered}" if rendered.include?('Liquid error')

      rendered
    end
  end
end
