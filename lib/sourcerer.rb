# frozen_string_literal: true

# This module is a pre-alpha version of what I will eventually spin off
#  as AsciiSourcery, for single-sourcing documentation AND product data
#  in AsciiDoc and YAML files
# It is pretty messy for now as I play around with various ways it might
#  get used, including as a build-time generator of artifacts to be used
#  in both the app and the docs

require 'asciidoctor'
require 'fileutils'
require 'yaml'
require_relative 'sourcerer/builder'
require_relative 'sourcerer/plaintext_converter'
require_relative 'sourcerer/templating'
require_relative 'sourcerer/jekyll'
require_relative 'schemagraphy'

# A tool for single-sourcing documentation and data from AsciiDoc and YAML files.
# It provides methods for extracting data, rendering templates, and generating various outputs.
module Sourcerer
  # Loads AsciiDoc attributes from a document header as a Hash.
  #
  # @param path [String] The path to the AsciiDoc file.
  # @return [Hash] A hash of the document attributes.
  def self.load_attributes path
    doc = Asciidoctor.load_file(path, safe: :unsafe)
    doc.attributes
  end

  # Loads a snippet from an AsciiDoc file using an `include::` directive.
  #
  # @param path_to_main_adoc [String] The path to the main AsciiDoc file.
  # @param tag [String] A single tag to include.
  # @param tags [Array<String>] An array of tags to include.
  # @param leveloffset [Integer] The level offset for the include.
  # @return [String] The content of the included snippet.
  def self.load_include path_to_main_adoc, tag: nil, tags: [], leveloffset: nil
    opts = []
    opts << "tag=#{tag}" if tag
    opts << "tags=#{tags.join(',')}" if tags.any?
    opts << "leveloffset=#{leveloffset}" if leveloffset

    snippet_doc = <<~ADOC
      include::#{path_to_main_adoc}[#{opts.join(', ')}]
    ADOC

    doc = Asciidoctor.load(
      snippet_doc,
      safe: :unsafe,
      base_dir: File.expand_path('.'),
      header_footer: false,
      attributes: { 'source-highlighter' => nil }) # disable extras

    # Get raw text from all top-level blocks
    doc.blocks.map(&:content).join("\n")
  end

  # Extracts tagged content from a file.
  #
  # @param path_to_tagged_adoc [String] The path to the file with tagged content.
  # @param tag [String] A single tag to extract.
  # @param tags [Array<String>] An array of tags to extract.
  # @param comment_prefix [String] The prefix for comment lines.
  # @param comment_suffix [String] The suffix for comment lines.
  # @param skip_comments [Boolean] Whether to skip comment lines in the output.
  # @return [String] The extracted content.
  # rubocop:disable Lint/UnusedMethodArgument
  def self.extract_tagged_content path_to_tagged_adoc, tag: nil, tags: [], comment_prefix: '// ', comment_suffix: '',
    skip_comments: false
    # rubocop:enable Lint/UnusedMethodArgument
    # NOTE: comment_suffix parameter is currently unused but kept for future functionality
    raise ArgumentError, 'tag and tags cannot coexist' if tag && !tags.empty?

    tags = [tag] if tag
    raise ArgumentError, 'at least one tag must be specified' if tags.empty?
    raise ArgumentError, 'tags must all be strings' unless tags.is_a?(Array) && tags.all? { |t| t.is_a?(String) }

    tagged_content = []
    open_tags = {}
    tag_comment_prefix = comment_prefix.strip || '//'
    tag_pattern = /^#{Regexp.escape(tag_comment_prefix)}\s*tag::([\w-]+)\[\]/
    end_pattern = /^#{Regexp.escape(tag_comment_prefix)}\s*end::([\w-]+)\[\]/
    comment_line_init_pattern = /^#{Regexp.escape(tag_comment_prefix)}+/
    collecting = false
    File.open(path_to_tagged_adoc, 'r') do |file|
      file.each_line do |line|
        # check for tag:: line
        if line =~ tag_pattern
          tag_name = Regexp.last_match(1)
          if tags.include?(tag_name)
            collecting = true
            open_tags[tag_name] = true
          end
        elsif line =~ end_pattern
          tag_name = Regexp.last_match(1)
          if open_tags[tag_name]
            open_tags.delete(tag_name)
            collecting = false if open_tags.empty?
          end
        elsif collecting
          tagged_content << line unless skip_comments && line =~ comment_line_init_pattern
        end
      end
      tagged_content = if tagged_content.empty?
                         ''
                       else
                         # return a string of concatenated lines
                         tagged_content.join
                       end
    end

    tagged_content
  end

  # Generates a manpage from an AsciiDoc source file.
  #
  # @param source_adoc [String] The path to the source AsciiDoc file.
  # @param target_manpage [String] The path to the target manpage file.
  def self.generate_manpage source_adoc, target_manpage
    FileUtils.mkdir_p File.dirname(target_manpage)
    Asciidoctor.convert_file(
      source_adoc,
      backend: 'manpage',
      safe: :unsafe,
      standalone: true,
      to_file: target_manpage)
  end

  # Renders a set of templates based on a configuration.
  #
  # @param templates_config [Array<Hash>] An array of template configurations.
  def self.render_templates templates_config
    render_outputs(templates_config)
  end

  # Renders templates or converter outputs based on a configuration.
  #
  # @param render_config [Array<Hash>] A list of render configurations.
  def self.render_outputs render_config
    return if render_config.nil? || render_config.empty?

    render_config.each do |render_entry|
      if render_entry[:converter]
        render_with_converter(render_entry)
        next
      end

      data_obj = render_entry[:key] || 'data'
      attrs_source = render_entry[:attrs]
      engine = render_entry[:engine] || 'liquid'

      render_template(
        render_entry[:template],
        render_entry[:data],
        render_entry[:out],
        data_object: data_obj,
        attrs_source: attrs_source,
        engine: engine)
    end
  end

  # Renders a single template with data.
  #
  # @param template_file [String] The path to the template file.
  # @param data_file [String] The path to the data file (YAML).
  # @param out_file [String] The path to the output file.
  # @param data_object [String] The name of the data object in the template.
  # @param includes_load_paths [Array<String>] Paths for Liquid includes.
  # @param attrs_source [String] The path to an AsciiDoc file for attributes.
  # @param engine [String] The template engine to use.
  def self.render_template template_file, data_file, out_file, data_object: 'data', includes_load_paths: [],
    attrs_source: nil, engine: 'liquid'
    data = load_render_data(data_file, attrs_source)
    out_file = File.expand_path(out_file)
    FileUtils.mkdir_p(File.dirname(out_file))

    template_path = File.expand_path(template_file)
    template_content = File.read(template_path)

    # Prepare context
    context = {
      data_object => data,
      'include' => { data_object => data } # for compatibility with {% include ... %} expecting include.var
    }

    rendered = case engine.to_s
               when 'erb' then render_erb(template_content, context)
               when 'liquid' then render_liquid(template_file, template_content, context, includes_load_paths)
               else raise ArgumentError, "Unsupported template engine: #{engine}"
               end

    File.write(out_file, rendered)
  end

  def self.render_with_converter render_entry
    data_file = render_entry[:data]
    out_file = render_entry[:out]
    raise ArgumentError, 'render entry missing :data' unless data_file
    raise ArgumentError, 'render entry missing :out' unless out_file

    data = load_render_data(data_file, render_entry[:attrs])
    converter = resolve_converter(render_entry[:converter])
    rendered = converter.call(data, render_entry)
    raise ArgumentError, 'converter returned non-string output' unless rendered.is_a?(String)

    out_file = File.expand_path(out_file)
    FileUtils.mkdir_p(File.dirname(out_file))
    File.write(out_file, rendered)
  end

  def self.load_render_data data_file, attrs_source
    if attrs_source
      attrs = load_attributes(attrs_source)
      SchemaGraphy::Loader.load_yaml_with_attributes(data_file, attrs)
    else
      SchemaGraphy::Loader.load_yaml_with_tags(data_file)
    end
  end

  def self.resolve_converter converter
    return converter if converter.respond_to?(:call)
    return Object.const_get(converter) if converter.is_a?(String)

    raise ArgumentError, "Unsupported converter: #{converter.inspect}"
  end

  def self.render_erb template_content, context
    require 'erb'
    ERB.new(template_content, trim_mode: '-').result_with_hash(context)
  end

  def self.render_liquid template_file, template_content, context, includes_load_paths
    require_relative 'sourcerer/jekyll'
    require_relative 'sourcerer/jekyll/liquid/filters'
    require_relative 'sourcerer/jekyll/liquid/tags'
    require 'liquid' unless defined?(Liquid::Template)
    Sourcerer::Jekyll.initialize_liquid_runtime

    # Determine includes root; add template directory to search paths
    fallback_templates_dir = File.expand_path('.', Dir.pwd)
    template_dir = File.dirname(File.expand_path(template_file))
    # For templates that use includes like cfgyml/config-property.adoc.liquid,
    # we need the parent directory of the template's directory as well
    template_parent_dir = File.dirname(template_dir)

    paths = if includes_load_paths.any?
              includes_load_paths
            else
              [template_parent_dir, template_dir, fallback_templates_dir]
            end

    # Create a fake Jekyll site
    site = Sourcerer::Jekyll::Bootstrapper.fake_site(
      includes_load_paths: paths,
      plugin_dirs: [])

    # Setup file system for includes with multiple paths
    file_system = Sourcerer::Jekyll::Liquid::FileSystem.new(paths)

    template = Liquid::Template.parse(template_content)
    options = {
      registers: {
        site: site,
        file_system: file_system
      }
    }
    template.render(context, options)
  end

  # Extracts commands from listing and literal blocks with a specific role.
  #
  # @param file_path [String] The path to the AsciiDoc file.
  # @param role [String] The role to look for.
  # @return [Array<String>] An array of command groups.
  def self.extract_commands file_path, role: 'testable'
    doc = Asciidoctor.load_file(file_path, safe: :unsafe)
    command_groups = []
    current_group = []

    blocks = doc.find_by(context: :listing) + doc.find_by(context: :literal)

    blocks.each do |block|
      next unless block.has_role?(role)

      commands = process_block_content(block.content)
      if block.has_role?('testable-newshell')
        command_groups << current_group.join("\n") unless current_group.empty?
        command_groups << commands.join("\n") unless commands.empty?
        current_group = []
      else
        current_group.concat(commands)
      end
    end

    command_groups << current_group.join("\n") unless current_group.empty?
    command_groups
  end

  # @api private
  # Processes the content of a block to extract commands.
  # It handles line continuations and skips comments.
  # @param content [String] The content of the block.
  # @return [Array<String>] An array of commands.
  def self.process_block_content content
    processed_commands = []
    current_command = ''
    content.each_line do |line|
      stripped_line = line.strip
      next if stripped_line.start_with?('#') # Skip comments

      if stripped_line.end_with?('\\')
        current_command += "#{stripped_line.chomp('\\')} "
      else
        current_command += stripped_line
        processed_commands << current_command unless current_command.empty?
        current_command = ''
      end
    end
    processed_commands
  end
end
