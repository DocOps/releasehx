# frozen_string_literal: true

module Sourcerer
  module Jekyll
    # This module contains monkeypatches for Jekyll to modify or extend its behavior.
    module Monkeypatches
      # Patches Jekyll's `OptimizedIncludeTag` to modify its behavior.
      # The patch enhances include path resolution and context handling to better
      # suit the needs of Sourcerer's templating environment.
      def self.patch_jekyll
        return unless defined?(::Jekyll::Tags::OptimizedIncludeTag)

        ::Jekyll::Tags::OptimizedIncludeTag.class_eval do
          define_method :render do |context|
            site = context.registers[:site]
            file = render_variable(context) || @file

            context.stack do
              context['include'] = parse_params(context) if @params

              source = site.inclusions[file]

              unless source

                # Debug lines before attempting path resolution

                # Safe resolution
                paths = context.registers[:includes_load_paths] || []
                path = paths
                       .map { |dir| File.join(dir, file) }
                       .find { |p| File.file?(p) }

                raise IOError, "Include file not found: #{file}" unless path

                source = File.read(path)
              end

              partial = ::Liquid::Template.parse(source)
              partial.registers[:site] = context.registers[:site]
              partial.assigns['include'] = context['include']

              ::Liquid::Template.register_filter(::Jekyll::Filters)
              ::Liquid::Template.register_filter(::Sourcerer::Jekyll::Liquid::Filters)

              # Use an isolated context so we can inspect and copy assigns
              subcontext = ::Liquid::Context.new(
                [{ 'include' => context['include'] }],
                {}, # Environments
                context.registers,
                rethrow_errors: true)

              rendered = partial.render!(subcontext)

              # Copy assigns from subcontext to parent context
              subcontext.environments.each do |env|
                env.each do |k, v|
                  # Avoid clobbering outer include if reentrant
                  next if k == 'include'

                  context.environments.first[k] = v
                end
              end

              rendered
            end
          end
        end

        ::Liquid::Template.tags['include'] = ::Jekyll::Tags::OptimizedIncludeTag
      end
    end
  end
end
