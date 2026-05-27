# frozen_string_literal: true

module ReleaseHx
  # Provides rich-text output generation from Release objects and draft source files.
  #
  # The EnrichOps module handles the conversion of Release data and various draft formats
  #  (YAML, Markdown, AsciiDoc) into rich output formats (HTML, PDF) using appropriate
  #  rendering engines and template processing.
  module EnrichOps
    # Generates rich-text output directly from a Release object.
    #
    # Processes Release data through Liquid templates to produce HTML or PDF output.
    # HTML generation uses direct template rendering, while PDF generation creates
    #  intermediate AsciiDoc content before conversion.
    #
    # @param release [ReleaseHx::RHYML::Release] The Release object to enrich.
    # @param config [ReleaseHx::Configuration] The application configuration.
    # @param format [Symbol] The output format (:html or :pdf).
    # @param outpath [String, nil] The explicit output file path; auto-resolved if nil.
    # @param force [Boolean] Whether to overwrite existing output files.
    # @return [String] The path to the generated output file.
    def self.enrich_from_rhyml release:, config:, format:, outpath: nil, force: false
      # Use proper config-based output path resolution if not provided
      outpath ||= resolve_enrich_path(release.code, format, config)

      if File.exist?(outpath) && !force
        ReleaseHx.logger.warn("File exists: #{outpath}. Use --force to overwrite.")
        return outpath
      end

      ReleaseHx.logger.debug("Enriching release #{release.code} to #{outpath} (format: #{format.to_s.upcase})")

      case format
      when :html
        # Direct Liquid template rendering to HTML
        html_content = DraftOps.process_template_content(release: release, config: config, format: :html)

        # Wrap HTML with Bootstrap styling if enabled
        enriched = if config && config.dig('modes', 'html_wrap') != false
                     ReleaseHx.logger.debug('Applying HTML wrapper')
                     wrap_html(html_content, config)
                   else
                     html_content
                   end

        WriteOps.safe_write(outpath, enriched)
      when :pdf
        # Two-stage process: RHYML → AsciiDoc → PDF
        asciidoc_content = DraftOps.process_template_content(release: release, config: config, format: :adoc)
        convert_asciidoc(asciidoc_content, format: :pdf, outpath: outpath)
      else
        raise ArgumentError, "Unsupported enrich format: #{format}"
      end

      outpath
    end

    # Generates rich-text output from source draft files of various formats.
    #
    # Automatically detects the input file type and applies the appropriate conversion
    #  strategy, supporting YAML (via RHYML) and AsciiDoc source formats.
    #
    # @param file_path [String] The path to the source draft file.
    # @param format [Symbol] The target output format (:html or :pdf).
    # @param config [ReleaseHx::Configuration] The application configuration.
    # @param outpath [String, nil] The explicit output file path; inferred if nil.
    # @param force [Boolean] Whether to overwrite existing output files.
    # @return [String] The path to the generated output file.
    def self.enrich_from_file file_path, format:, config:, outpath: nil, force: false
      raise "File not found: #{file_path}" unless File.exist?(file_path)

      file_ext = File.extname(file_path).downcase
      outpath ||= file_path.sub(/\.[^.]+$/, ".#{format}")

      # Prevent accidental file overwrites
      if File.exist?(outpath) && !force
        ReleaseHx.logger.warn("File exists: #{outpath}. Use --force to overwrite.")
        return outpath
      end

      # Route to appropriate conversion method based on source format
      case file_ext
      when '.yml', '.yaml'
        # RHYML/YAML files: load as Release object and use Liquid templates
        release = load_rhyml_from_yaml(file_path, config: config)
        enrich_from_rhyml(release: release, config: config, format: format, outpath: outpath, force: true)
      when '.adoc'
        # AsciiDoc files: use native converter
        convert_asciidoc(file_path, format: format, config: config, outpath: outpath, force: true)
      else
        raise "Unsupported source file format: #{file_ext}"
      end
    end

    # Converts AsciiDoc content or files to rich-text formats using configured engines.
    #
    # Accepts either file paths or raw content strings as input. Selects appropriate
    # converter engine based on config.conversions.engines.html/pdf settings with intelligent defaults:
    # - AsciiDoc → HTML: asciidoctor-html5s (default)
    # - AsciiDoc → PDF: asciidoctor-pdf (default)
    #
    # HTML output can be wrapped with Bootstrap CSS when config.modes.html_wrap is enabled.
    #
    # @param file_path_or_content [String] File path or raw AsciiDoc content.
    # @param format [Symbol] The target output format (:html or :pdf).
    # @param outpath [String] The target output file path.
    # @param config [ReleaseHx::Configuration] Configuration for engines and wrapping options.
    # @param force [Boolean] Whether to overwrite existing files.
    # @return [String] The path to the generated output file.
    def self.convert_asciidoc file_path_or_content, format:, outpath:, config: nil, force: nil
      # Determine if input is file path or raw content
      is_file = file_path_or_content.is_a?(String) && File.exist?(file_path_or_content)
      content = is_file ? File.read(file_path_or_content) : file_path_or_content

      case format.to_sym
      when :html
        engine = resolve_engine(format: :html, source_format: :asciidoc, config: config)
        html_fragment = convert_with_engine(content, engine: engine, format: :html)

        # Wrap HTML with Bootstrap styling if enabled
        enriched = if config && config.dig('modes', 'html_wrap') != false
                     ReleaseHx.logger.debug('Applying wrapper to AsciiDoc-derived HTML')
                     wrap_html(html_fragment, config)
                   else
                     html_fragment
                   end
      when :pdf
        engine = resolve_engine(format: :pdf, source_format: :asciidoc, config: config)
        convert_with_engine(content, engine: engine, format: :pdf, outpath: outpath)
        return outpath
      else
        raise "Unsupported format for AsciiDoc: #{format}"
      end

      # Prevent accidental file overwrites for HTML output
      if File.exist?(outpath) && !force
        ReleaseHx.logger.warn("File exists: #{outpath}. Use --force to overwrite.")
        return outpath
      end
      WriteOps.safe_write(outpath, enriched)
      outpath
    end

    # Loads RHYML data from a YAML file and creates a Release object.
    #
    # Processes YAML files containing either a single Release or a collection
    # of Releases, extracting the first Release for processing.
    #
    # @param file_path [String] Path to the YAML file containing RHYML data.
    # @param config [ReleaseHx::Configuration] Reserved for future use.
    # @return [ReleaseHx::RHYML::Release] The constructed Release object.
    # rubocop:disable Lint/UnusedMethodArgument
    def self.load_rhyml_from_yaml file_path, config:
      # NOTE: config parameter is currently unused but kept for API consistency
      # Load RHYML data using SchemaGraphy for tag processing
      rhyml_data = SchemaGraphy::Loader.load_yaml_with_tags(file_path)

      # Extract Release data: first item from 'releases' array or single Release hash
      release_data = rhyml_data['releases'] ? rhyml_data['releases'].first : rhyml_data

      # Construct Release object with keyword arguments
      ReleaseHx::RHYML::Release.new(
        code: release_data['code'],
        date: release_data['date'],
        hash: release_data['hash'],
        memo: release_data['memo'],
        changes: release_data['changes'] || [])
    end
    # rubocop:enable Lint/UnusedMethodArgument

    # Resolves the output file path using configuration-based templated filenames.
    #
    # Constructs the full output path by combining configured directories and
    # processing template variables in the filename pattern.
    #
    # @param version [String] The release version code for template substitution.
    # @param format [Symbol] The output format for file extension determination.
    # @param config [ReleaseHx::Configuration] Configuration containing path templates.
    # @return [String] The resolved absolute output file path.
    def self.resolve_enrich_path version, format, config
      # Extract path configuration from config
      output_dir = config.dig('paths', 'output_dir')
      enrich_dir = config.dig('paths', 'enrich_dir')
      filename_template = config.dig('paths', 'enrich_filename')

      # Build template context for filename processing
      context = {
        'version' => version,
        'format_ext' => format.to_s
      }

      # Process templated filename and construct full path
      filename = SchemaGraphy::Templating.render_field_if_template(filename_template, context)
      File.join(output_dir, enrich_dir, filename.strip)
    end

    # Wraps an HTML fragment with Bootstrap CSS and semantic HTML structure.
    #
    # Takes a raw HTML fragment and wraps it with proper DOCTYPE, head section with Bootstrap CDN link, and body tag.
    # Uses the wrapper.html.liquid template for markup generation.
    #
    # @param html_fragment [String] The raw HTML content to wrap.
    # @param config [ReleaseHx::Configuration] Configuration object for title and settings.
    # @return [String] Complete HTML document with Bootstrap styling.
    def self.wrap_html html_fragment, config
      # Extract and parse framework setting
      framework_spec = config.dig('history', 'html_framework') || 'bare'
      framework_name, framework_version = parse_framework_spec(framework_spec)

      template_path = WriteOps.resolve_template_path('wrapper.html.liquid', config)

      template_vars = {
        'config' => config,
        'content' => html_fragment,
        'framework' => framework_name,
        'framework_version' => framework_version
      }

      WriteOps.process_template(template_path, template_vars, config)
    end

    # Parses framework specification string into name and version.
    #
    # @param spec [String] Framework specification like 'bootstrap5' or 'bootstrap:5.3.0'
    # @return [Array<String, String>] Tuple of [framework_name, framework_version]
    def self.parse_framework_spec spec
      case spec.to_s
      when /^(.+):(.+)$/
        # Format: "bootstrap:5.3.0"
        [::Regexp.last_match(1), ::Regexp.last_match(2)]
      when 'bootstrap5'
        ['bootstrap', '5.3.0']
      when 'bootstrap4'
        ['bootstrap', '4.6.2']
      else
        ['bare', nil]
      end
    end

    # Resolves the appropriate conversion engine based on format and source.
    #
    # Applies intelligent defaults based on source format:
    # - AsciiDoc → HTML: asciidoctor-html5s
    # - AsciiDoc → PDF: asciidoctor-pdf
    # - Markdown → HTML: kramdown
    # - Markdown → PDF: pandoc
    #
    # @param format [Symbol] Output format (:html or :pdf)
    # @param source_format [Symbol] Source format (:asciidoc or :markdown)
    # @param config [Hash] Configuration hash
    # @return [String] Engine name
    def self.resolve_engine format:, source_format:, config: nil
      # Check for explicit engine configuration
      explicit_engine = config&.dig('conversions', 'engines', format.to_s)
      return explicit_engine if explicit_engine

      # Apply intelligent defaults based on source format
      case [source_format, format]
      when %i[asciidoc html]
        'asciidoctor-html5s'
      when %i[asciidoc pdf]
        'asciidoctor-pdf'
      when %i[markdown html]
        'kramdown'
      when %i[markdown pdf]
        'pandoc'
      else
        raise "Unsupported conversion: #{source_format} → #{format}"
      end
    end

    # Converts content using the specified engine.
    #
    # @param content [String] Source content to convert
    # @param engine [String] Engine name (e.g., 'asciidoctor-html5s', 'asciidoctor-pdf')
    # @param format [Symbol] Output format (:html or :pdf)
    # @param outpath [String, nil] Output file path (required for PDF)
    # @return [String] Converted content (for HTML) or output path (for PDF)
    # rubocop:disable Lint/UnusedMethodArgument
    def self.convert_with_engine content, engine:, format:, outpath: nil
      case engine
      when 'asciidoctor-html5', 'asciidoctor-html5s'
        require 'asciidoctor'
        backend = engine.split('-').last # 'html5' or 'html5s'

        if backend == 'html5s'
          begin
            require 'asciidoctor-html5s'
            ReleaseHx.logger.debug('Using asciidoctor-html5s backend for semantic HTML5')
          rescue LoadError
            ReleaseHx.logger.warn('asciidoctor-html5s not available, falling back to html5')
            backend = 'html5'
          end
        end

        Asciidoctor.convert(content, safe: :safe, backend: backend)

      when 'asciidoctor-pdf'
        require 'asciidoctor'
        require 'asciidoctor-pdf'
        ReleaseHx.logger.debug('Using asciidoctor-pdf for PDF generation')
        Asciidoctor.convert(content, to_file: outpath, safe: :safe, backend: 'pdf')
        outpath

      when 'asciidoctor-web-pdf'
        require 'asciidoctor'
        require 'asciidoctor-web-pdf'
        ReleaseHx.logger.debug('Using asciidoctor-web-pdf for PDF generation')
        Asciidoctor.convert(content, to_file: outpath, safe: :safe, backend: 'web-pdf')
        outpath

      when 'kramdown'
        require 'kramdown'
        ReleaseHx.logger.debug('Using Kramdown for HTML conversion')
        Kramdown::Document.new(content).to_html

      when 'pandoc'
        # Future implementation - would shell out to pandoc
        raise 'Pandoc engine not yet implemented'

      else
        raise "Unsupported engine: #{engine}"
      end
    end
    # rubocop:enable Lint/UnusedMethodArgument
  end
end
