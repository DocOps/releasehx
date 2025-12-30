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
        WriteOps.safe_write(outpath, html_content)
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
    #  strategy, supporting YAML (via RHYML), Markdown, and AsciiDoc source formats.
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
      when '.md'
        # Markdown files: use native converter
        convert_markdown(file_path, format: format, config: config, outpath: outpath, force: true)
      when '.adoc'
        # AsciiDoc files: use native converter
        convert_asciidoc(file_path, format: format, config: config, outpath: outpath, force: true)
      else
        raise "Unsupported source file format: #{file_ext}"
      end
    end

    # Converts Markdown files to rich-text formats using native converters.
    #
    # Uses Kramdown for HTML generation and Tilt with Pandoc for PDF conversion.
    # Note: Some parameters are reserved for API consistency across conversion methods.
    #
    # @param file_path [String] The path to the source Markdown file.
    # @param format [Symbol] The target output format (:html or :pdf).
    # @param config [ReleaseHx::Configuration] Reserved for future use.
    # @param outpath [String] The target output file path.
    # @param force [Boolean] Reserved for future use.
    # @return [String] The path to the generated output file.
    # rubocop:disable Lint/UnusedMethodArgument
    def self.convert_markdown file_path, format:, config:, outpath:, force:
      # NOTE: config and force parameters are currently unused but kept for API consistency
      content = File.read(file_path)

      case format.to_sym
      when :html
        require 'kramdown'
        enriched = Kramdown::Document.new(content).to_html
        WriteOps.safe_write(outpath, enriched)
      when :pdf
        # Use Tilt with Pandoc for direct Markdown to PDF conversion
        require 'tilt'
        require 'tilt/pandoc'

        template = Tilt::PandocTemplate.new(file_path)
        enriched = template.render(nil, to: 'pdf')
        WriteOps.safe_write(outpath, enriched)
        ReleaseHx.logger.info("PDF generated via Tilt/Pandoc: #{outpath}")
      else
        raise "Unsupported format for Markdown: #{format}"
      end

      outpath
    end
    # rubocop:enable Lint/UnusedMethodArgument

    # Converts AsciiDoc content or files to rich-text formats using Asciidoctor.
    #
    # Accepts either file paths or raw content strings as input. Uses Asciidoctor
    # for HTML generation and Asciidoctor-PDF for direct PDF output.
    #
    # @param file_path_or_content [String] File path or raw AsciiDoc content.
    # @param format [Symbol] The target output format (:html or :pdf).
    # @param outpath [String] The target output file path.
    # @param config [ReleaseHx::Configuration] Reserved for future use.
    # @param force [Boolean] Reserved for future use.
    # @return [String] The path to the generated output file.
    # rubocop:disable Lint/UnusedMethodArgument
    def self.convert_asciidoc file_path_or_content, format:, outpath:, config: nil, force: nil
      # NOTE: config and force parameters are currently unused but kept for API consistency
      # Determine if input is file path or raw content
      is_file = file_path_or_content.is_a?(String) && File.exist?(file_path_or_content)
      content = is_file ? File.read(file_path_or_content) : file_path_or_content

      case format.to_sym
      when :html
        require 'asciidoctor'
        enriched = Asciidoctor.convert(content, safe: :safe, backend: 'html5')
      when :pdf
        require 'asciidoctor'
        require 'asciidoctor-pdf'
        Asciidoctor.convert(content, to_file: outpath, safe: :safe, backend: 'pdf')
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
    # rubocop:enable Lint/UnusedMethodArgument

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
  end
end
