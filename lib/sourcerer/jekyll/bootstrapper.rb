# frozen_string_literal: true

require 'jekyll'
require 'jekyll-asciidoc'

module Sourcerer
  module Jekyll
    # This module provides methods for programmatically setting up a Jekyll site
    # environment, which is useful for loading plugins or creating a mock site for rendering.
    module Bootstrapper
      # Loads Jekyll plugins from specified directories.
      #
      # @param plugin_dirs [Array<String>] A list of directories to search for plugins.
      # @return [Jekyll::Site] The initialized Jekyll site object.
      def self.load_plugins plugin_dirs: []
        config = ::Jekyll.configuration(
          {
            'source'      => Dir.pwd,
            'destination' => File.join(Dir.pwd, '_site'),
            'quiet'       => true,
            'skip_config_files' => true,
            'plugins_dir' => plugin_dirs.map { |d| File.expand_path(d) },
            'disable_disk_cache' => true
          })

        site = ::Jekyll::Site.new(config)
        site.plugin_manager.conscientious_require

        ::Jekyll::Hooks.trigger :site, :after_init, site

        site
      end

      # Creates an ephemeral Jekyll site instance for rendering purposes.
      # This is useful for leveraging Jekyll's templating outside of a full site build.
      #
      # @param includes_load_paths [Array<String>] Paths to load includes from.
      # @param plugin_dirs [Array<String>] Paths to load plugins from.
      # @return [Jekyll::Site] The initialized fake Jekyll site object.
      # rubocop:disable Lint/UnusedMethodArgument
      def self.fake_site includes_load_paths: [], plugin_dirs: []
        # NOTE: plugin_dirs parameter is accepted but not yet implemented; reserved for future plugin loading
        ::Jekyll.logger.log_level = :error if ::Jekyll.logger.respond_to?(:log_level=)

        config = ::Jekyll.configuration(
          'source'              => Dir.pwd,
          'includes_dir'        => includes_load_paths.first,
          'includes_load_paths' => includes_load_paths,
          'destination'         => File.join(Dir.pwd, '_site'),
          'quiet'               => true,
          'skip_config_files'   => true,
          'disable_disk_cache'  => true)

        site = ::Jekyll::Site.new(config)

        include_paths = site.includes_load_paths || []
        site.inclusions ||= {}

        include_paths.each do |dir|
          Dir[File.join(dir, '**/*')].each do |file|
            next unless File.file?(file)

            relative_path = file.sub("#{dir}/", '')
            site.inclusions[relative_path] = File.read(file)
          end
        end

        site.instance_variable_set(:@liquid_renderer, ::Jekyll::LiquidRenderer.new(site))

        plugin_manager = ::Jekyll::PluginManager.new(site)
        plugin_manager.conscientious_require

        site
      end
      # rubocop:enable Lint/UnusedMethodArgument
    end
  end
end
