# frozen_string_literal: true

require_relative 'jekyll/bootstrapper'
require_relative 'jekyll/monkeypatches'
require_relative 'jekyll/liquid/file_system'
require_relative 'jekyll/liquid/filters'
require_relative 'jekyll/liquid/tags'
require 'jekyll-asciidoc'

module Sourcerer
  # This module encapsulates the logic for initializing a Jekyll-like Liquid
  # templating environment. It loads necessary plugins, applies monkeypatches,
  # and registers custom Liquid filters and tags.
  module Jekyll
    # Initializes the Liquid templating runtime by loading plugins,
    # applying patches, and registering custom filters.
    def self.initialize_liquid_runtime
      Bootstrapper.load_plugins
      Monkeypatches.patch_jekyll
      # Ensure Sourcerer filters are registered
      ::Liquid::Template.register_filter(::Sourcerer::Jekyll::Liquid::Filters)
      # Ensure jekyll-asciidoc filters are registered
      # ::Liquid::Template.register_filter(Jekyll::AsciiDoc::Filters)
    end
  end
end
