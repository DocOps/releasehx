# frozen_string_literal: true

require 'yaml'
require 'json'
require 'fileutils'
require_relative '../releasehx'

module ReleaseHx
  class CLI < Thor
    def self.exit_on_failure?
      true
    end

    # =======================================
    # OVERRIDE .start to handle no-arguments
    # and default subcommand behavior
    # =======================================
    def self.start original_args = ARGV, config = {}
      # If user gave no arguments at all, or only gave --help, allow that through
      if original_args.empty? || (original_args.length == 1 && original_args.first =~ /^--?h(elp)?$/)
        show_usage_snippet
        return
      elsif original_args.length == 1 && original_args.first =~ /^--man(page)?$/
        show_manpage
        return
      elsif original_args.length == 1 && original_args.first =~ /^--version$/
        puts ReleaseHx::VERSION
        return
      else
        first = original_args[0]
        original_args.unshift 'default' unless first.start_with?('-') || all_tasks.key?(first)
      end

      super
    end

    default_task :default

    desc 'VERSION|PATH [options]', ReleaseHx.attrs['tagline']
    method_option :md,    type: :string, lazy_default: '',
      desc: ReleaseHx.attrs['cli_option_message_md']
    method_option :adoc,  type: :string, aliases: ['--ad'], lazy_default: '',
      desc: ReleaseHx.attrs['cli_option_message_adoc']
    method_option :yaml,  type: :string, aliases: ['--yml'], lazy_default: '',
      desc: ReleaseHx.attrs['cli_option_message_yaml']
    method_option :html,  type: :string, lazy_default: '',
      desc: ReleaseHx.attrs['cli_option_message_html']
    method_option :pdf,   type: :string, lazy_default: '',
      desc: ReleaseHx.attrs['cli_option_message_pdf']
    method_option :output_dir, type: :string, lazy_default: '',
      desc: ReleaseHx.attrs['cli_option_message_output_dir']
    method_option :api_data, type: :string, banner: 'PATH',
      desc: ReleaseHx.attrs['cli_option_message_api_data']
    method_option :config, type: :string, banner: 'PATH',
      desc: ReleaseHx.attrs['cli_option_message_config']
    method_option :mapping, type: :string, banner: 'PATH',
      desc: ReleaseHx.attrs['cli_option_message_mapping']
    method_option :payload, type: :string, lazy_default: '',
      desc: ReleaseHx.attrs['cli_option_message_payload']
    method_option :fetch,  type: :boolean,
      desc: ReleaseHx.attrs['cli_option_message_fetch']
    method_option :append, type: :boolean,
      desc: ReleaseHx.attrs['cli_option_message_append']
    method_option :over,   type: :boolean, aliases: ['--force'],
      desc: ReleaseHx.attrs['cli_option_message_over']
    method_option :check,  type: :boolean, aliases: ['--scan'],
      desc: ReleaseHx.attrs['cli_option_message_check']
    method_option :emptynotes, type: :string, aliases: ['--empty', '-e'], lazy_default: '',
      desc: ReleaseHx.attrs['cli_option_message_emptynotes']
    method_option :internal, type: :boolean,
      desc: ReleaseHx.attrs['cli_option_message_internal']
    method_option :wrap, type: :boolean, default: nil,
      desc: ReleaseHx.attrs['cli_option_message_wrap']
    method_option :frontmatter, type: :boolean, default: nil, desc: ReleaseHx.attrs['cli_option_message_frontmatter']
    method_option :verbose, type: :boolean,
      desc: ReleaseHx.attrs['cli_option_message_verbose']
    method_option :debug,   type: :boolean,
      desc: ReleaseHx.attrs['cli_option_message_debug']
    method_option :debug_dump, type: :boolean, desc: ReleaseHx.attrs['cli_option_message_debug_dump']
    method_option :quiet, type: :boolean,
      desc: ReleaseHx.attrs['cli_option_message_quiet']

    # FIXME: This method is overly complex and handles too many concerns.
    # It should be broken down into smaller methods, each handling a specific
    # CLI action or workflow. A major refactor is planned for post-0.1.0.
    def default source_arg
      setup_logger
      ReleaseHx.logger.debug "Starting ReleaseHx with version/source: #{source_arg}"
      load_and_configure_settings(ReleaseHx.attrs['app_default_config_path'])

      if options[:debug]
        begin
          config_dump = SgymlHelpers.deep_stringify_safe(@settings).to_yaml
          ReleaseHx.logger.debug "Operative config settings:\n#{config_dump}"
        rescue StandardError => e
          require 'pp' # pretty print
          ReleaseHx.logger.debug "Rescued config PP dump:\n#{PP.pp(@settings, +'')}"
          raise e
        end
      end

      source_arg_type = version_or_file(source_arg)
      if source_arg_type == :invalid
        raise Thor::Error, <<~ERRTXT
          ERROR: Invalid file extension for source file: #{source_arg}
                 Valid draft file types are: #{ReleaseHx.attrs['draft_source_file_types']}
                 Valid extensions are: #{ReleaseHx.attrs['draft_source_extensions']}
        ERRTXT
      end

      ReleaseHx.logger.info "Source type: #{source_arg_type}"

      if options[:verbose] && @settings['origin']
        ReleaseHx.logger.debug "✓ Source configured: #{@settings['origin']['source']}"
      end

      if options[:check]
        if source_arg_type == :file
          raise Thor::Error,
                'ERROR: Scan operations require a version number as the first argument.'
        end

        perform_scan(source_arg)
        return
      end

      if options[:api_data] && (options[:api_data].nil? || options[:api_data].empty?)
        raise Thor::Error, 'Must specify a PATH for --api-data. E.g. --api-data cached-1-1-1.json'
      end

      if options[:api_data] && !File.exist?(options[:api_data])
        raise Thor::Error, "API data file not found: #{options[:api_data]}"
      end

      if options[:api_data]
        ReleaseHx.logger.debug "✓ Using cached API data: #{options[:api_data]}"
      elsif options[:fetch]
        ReleaseHx.logger.info "✓ Will fetch fresh data from #{@settings['origin']['source']} API" if options[:verbose]
      end

      if options[:api_data] && options[:fetch]
        ReleaseHx.logger.warn 'Warning: --fetch ignored when --api-data is specified'
      end

      if [options[:adoc], options[:md], options[:yaml]].compact.size > 1
        raise Thor::Error, 'ERROR: Only one of --adoc, --md, or --yaml (or aliases) may be specified.'
      end

      if options[:append]
        perform_append(source_arg)
        return
      end

      determine_operations(source_arg)
    end

    private

    def load_and_configure_settings default_config_path
      if options[:config] && !File.exist?(options[:config])
        raise Thor::Error, "ERROR: Configuration declared but not found: #{options[:config]}"
      end

      config_path = options[:config] || default_config_path
      if options[:config]
        ReleaseHx.logger.info "Using specified config file: #{config_path}"
      elsif options[:verbose]
        ReleaseHx.logger.info "Using default config file: #{config_path}"
      end

      ReleaseHx.logger.info 'Loading configuration...' if options[:verbose]
      @settings = ReleaseHx::Configuration.load(config_path).settings

      merge_cli_flags_into_settings

      apply_cli_overrides

      return unless options[:debug]

      begin
        config_dump = SgymlHelpers.deep_stringify_safe(@settings).to_yaml
        ReleaseHx.logger.debug "Operative config settings:\n#{config_dump}"
      rescue StandardError => e
        require 'pp' # pretty print
        ReleaseHx.logger.debug "Rescued config PP dump:\n#{PP.pp(@settings, +'')}"
        raise e
      end
    end

    def setup_logger
      # Ensure the global logger references the same object we configured
      log = ReleaseHx.logger

      log.level = if options[:debug_dump]
                    ReleaseHx::DUMP # lowest level, includes all output
                  elsif options[:debug]
                    Logger::DEBUG
                  elsif options[:quiet]
                    Logger::ERROR
                  else # default or :verbose
                    Logger::INFO
                  end

      # Log the logging level change for verbose output
      return unless options[:verbose]

      level_name = case log.level
                   when ReleaseHx::DUMP then 'DUMP'
                   when Logger::DEBUG then 'DEBUG'
                   when Logger::INFO then 'INFO'
                   when Logger::WARN then 'WARN'
                   when Logger::ERROR then 'ERROR'
                   else 'UNKNOWN'
                   end
      log.info "Logging level set to #{level_name}"
    end

    class << self
      private

      def show_usage_snippet
        usage_text = ReleaseHx.read_built_snippet(:helpscreen)
        puts "\nVersion: #{ReleaseHx::VERSION}"
        puts usage_text
        puts
      end

      def show_manpage
        gem_manfile = File.expand_path('../../build/docs/releasehx.1', __dir__)

        unless File.exist?(gem_manfile)
          warn "Man file not found in gem: #{gem_manfile}"
          return
        end
        display_manpage_locally(gem_manfile)
      end

      def display_manpage_locally manfile
        # FIXME: Eventually we want to provide a proper man page for Unix environments
        tmp_dir = File.join(Dir.home, '.rhxtmp')
        FileUtils.mkdir_p(tmp_dir)

        tmp_path = File.join(tmp_dir, 'releasehx.1')
        FileUtils.cp(manfile, tmp_path)

        # Use -l to display local file
        system("man -l '#{tmp_path}'")

        FileUtils.rm_f(tmp_path)
      end
    end

    # Determine whether first argument is a version # or a proper file path
    def version_or_file source_arg
      extensions = ReleaseHx.attrs['draft_source_extensions'].split(', ')
      if extensions.any? { |ext| source_arg.end_with?(ext) }
        :file
      elsif source_arg.end_with?('.html', '.pdf')
        :invalid
      else
        :version
      end
    end

    def perform_scan version
      ReleaseHx.logger.info("Scanning for missing release notes in version #{version}")

      # Use the same source determination logic as main operations
      source_type = determine_payload_type(version)

      case source_type
      when :yaml
        # For scan operations, we need the version code, not a file path
        raise Thor::Error, 'ERROR: Scan operations require a version number, not a YAML file path.'
      when :json
        if options[:api_data]
          payload = load_json_issues(options[:api_data])
        else
          raise Thor::Error,
                'ERROR: JSON source specified but no --api-data file provided. ' \
                'Use --api-data PATH to specify a JSON file.'
        end
      when :api
        # Get configured source type for API operations
        configured_source_type = @settings.dig('origin', 'source')
        case configured_source_type
        when 'jira', 'github', 'gitlab'
          payload = fetch_issues_from_api(version)
        else
          raise Thor::Error,
                "ERROR: API origin requires origin.source to be 'jira', 'github', or 'gitlab', " \
                "but got '#{configured_source_type}'"
        end
      else
        raise Thor::Error, "ERROR: Scanning not supported for source type '#{source_type}'"
      end

      mapping      = load_mapping
      release_code = basename_for_output(version)
      release_date = Date.today
      issues_count = payload.is_a?(Array) ? payload.size : payload['issues']&.size || payload.size

      emptynotes_arg = options[:emptynotes]

      # Interpret CLI override for --empty/-e
      if emptynotes_arg && !emptynotes_arg.empty?
        if %w[skip empty dump ai].include?(emptynotes_arg)
          # override setting
          @settings['rhyml']['empty_notes'] = emptynotes_arg
        else
          # Toggle logic
          current = @settings.dig('rhyml', 'empty_notes') || 'skip'
          @settings['rhyml']['empty_notes'] = current == 'skip' ? 'empty' : 'skip'
        end
      elsif emptynotes_arg && emptynotes_arg.empty?
        # Flag used without value; toggle logic
        current = @settings.dig('rhyml', 'empty_notes') || 'skip'
        @settings['rhyml']['empty_notes'] = current == 'skip' ? 'empty' : 'skip'
      end

      require_relative 'ops/check_ops'

      release = ReleaseHx::DraftOps.from_payload(
        payload: payload,
        config: @settings,
        mapping: mapping,
        release_code: release_code,
        release_date: release_date,
        scan: true)

      ReleaseHx::CheckOps.print_check_summary(release, issues_count, payload, @settings, mapping)
      nil
    end

    def perform_append source_arg
      ReleaseHx.logger.info('Appending new issues to existing YAML draft')

      # Determine the existing YAML file path
      yaml_file_path = resolve_yaml_file_path(source_arg)

      unless File.exist?(yaml_file_path)
        raise Thor::Error, "ERROR: YAML file not found: #{yaml_file_path}. Cannot append without existing file."
      end

      # Load the YAML to get the actual version code from the 'code' field
      yaml_data = SchemaGraphy::Loader.load_yaml_with_tags(yaml_file_path)
      version_code = yaml_data['code']

      raise Thor::Error, "ERROR: No 'code' field found in YAML file: #{yaml_file_path}" unless version_code

      ReleaseHx.logger.debug "Using version code from YAML: #{version_code}"

      source_type = determine_payload_type(version_code)
      payload = fetch_or_load_issues(version_code, source_type)

      # Delegate to DraftOps for the append logic
      new_changes_count = ReleaseHx::DraftOps.append_changes(
        yaml_file_path: yaml_file_path,
        version_code: version_code,
        config: @settings,
        mapping: load_mapping,
        source_type: source_type,
        payload: payload,
        force: options[:over])

      if new_changes_count.positive?
        ReleaseHx.logger.info "Successfully appended #{new_changes_count} changes to #{yaml_file_path}"
      else
        ReleaseHx.logger.info 'No new changes found to append.'
      end
    end

    def resolve_yaml_file_path source_arg
      if version_or_file(source_arg) == :file
        # Direct file path provided
        unless source_arg.end_with?('.yml', '.yaml', '.rhyml')
          raise Thor::Error, "ERROR: --append requires a YAML file. Got: #{source_arg}"
        end

        source_arg
      else
        # Version code; look for existing draft first
        existing = find_existing_drafts(source_arg)
        if existing && existing[:format] == :yml
          existing[:path]
        else
          # Use the same path resolution logic as draft generation
          resolve_draft_path(:yaml, source_arg)
        end
      end
    end

    # IMPORTANT: This method is currently not used
    def check_for_existing_draft version
      # Implementation pending the draft handling refactor
    end

    def determine_operations source_arg
      operation_mode = determine_mode(source_arg)

      case operation_mode
      when :draft_only
        ReleaseHx.logger.info('Generating draft only.')
        generate_draft(source_arg)
      when :enrich_only
        ReleaseHx.logger.info('Rendering document/s only.')
        enrich_docs(source_arg, source_arg)
      when :draft_and_enrich
        ReleaseHx.logger.info('Generating draft and enriched docs.')
        generate_draft(source_arg)
        enrich_docs(source_arg, source_arg)
      else
        raise Thor::Error, 'ERROR: Could not determine valid operation mode.'
      end
    end

    def determine_mode _source_arg
      return :enrich_only if enrich_requested? && !draft_requested?
      if options[:fetch] && !draft_requested? && !enrich_requested?
        raise Thor::Error, 'ERROR: You must specify a draft or enrich format when using --fetch.'
      end
      return :draft_and_enrich if options[:fetch] && enrich_requested?
      return :draft_and_enrich if draft_requested? && enrich_requested?
      return :draft_only if options[:fetch] || draft_requested?

      raise Thor::Error, 'ERROR: You must specify a draft or enrich format.'
    end

    # Returns true if any draft format flags exist
    def draft_requested?
      !options[:md].nil? || !options[:adoc].nil? || !options[:yaml].nil?
    end

    # Returns true if any enrich format flags exist
    def enrich_requested?
      !options[:html].nil? || !options[:pdf].nil?
    end

    def determine_input_type version_arg
      return { type: :file, format: file_format(version_arg), path: version_arg } if File.file?(version_arg)

      # It's a version number. Try resolving a usable draft.
      existing = find_existing_drafts(version_arg)
      return { type: :draft, format: existing[:format], path: existing[:path] } if existing

      { type: :api, format: :api, path: version_arg }
    end

    def basename_for_output source_arg
      if version_or_file(source_arg) == :file
        File.basename(source_arg, File.extname(source_arg))
      else
        source_arg
      end
    end

    def find_existing_drafts version
      base = File.join(@settings['paths']['drafts_dir'], version)

      %w[adoc md yml].each do |ext|
        path = "#{base}.#{ext}"
        return { format: ext.to_sym, path: path } if File.exist?(path)
      end

      nil
    end

    def generate_draft source_arg
      version = basename_for_output(source_arg) # used only for filenames and template context
      release = create_rhyml_from_source(source_arg, version)

      fmt = draft_format_requested
      outpath = resolve_draft_path(fmt, version)

      if File.exist?(outpath) && !options[:over]
        ReleaseHx.logger.warn "File exists: #{outpath}. Use --force to overwrite."
        return
      end

      ReleaseHx::DraftOps.draft_output(
        release:     release,
        config:      @settings,
        format:      fmt,
        outpath: outpath)
    end

    def resolve_draft_path flag, version
      user_path = options[flag]
      if user_path && !user_path.empty?
        ReleaseHx.logger.info "✓ Custom output path for #{flag}: #{user_path}" if options[:verbose]
        return user_path
      end

      format = case flag
               when :yaml then :yaml
               when :md   then :md
               when :adoc then :adoc
               else flag
               end

      ext = ReleaseHx.format_extension(format, @settings)

      template_obj = @settings.dig('paths', 'draft_filename')
      filename     = Sourcerer::Templating::Engines.render(
        template_obj, 'liquid',
        { 'version' => version, 'format_ext' => ext })

      # Get output_dir and drafts_dir, making drafts_dir relative to output_dir
      output_dir = @settings.dig('paths', 'output_dir')
      drafts_dir = @settings.dig('paths', 'drafts_dir')

      # Construct full path: output_dir/drafts_dir/filename
      File.join(output_dir, drafts_dir, filename.strip)
    end

    def draft_format_requested
      return :yaml if options[:yaml]
      return :md   if options[:md]
      return :adoc if options[:adoc]

      nil
    end

    def derive_release_code arg
      # If it's already a version code (no path separator or file extension), return as-is
      return arg unless arg.include?('/') || arg.end_with?('.yaml', '.yml', '.json', '.adoc', '.md')

      # Otherwise, it's a file path or filename; extract basename without extension
      File.basename(arg, File.extname(arg))
    end

    def load_mapping
      if options[:mapping]
        path = options[:mapping]
        raise Thor::Error, "Mapping file not found: #{path}" unless File.exist?(path)

        ReleaseHx.logger.info "✓ Using custom mapping file: #{path}" if options[:verbose]
        SchemaGraphy::Loader.load_yaml_with_tags(path)
      else
        origin_source = @settings.dig('origin', 'source') || 'default'
        local_dir = @settings.dig('paths', 'mappings_dir') || '_mappings'

        # Try both .yaml and .yml extensions for local mappings
        local_paths = [
          File.join(local_dir, "#{origin_source}.yaml"),
          File.join(local_dir, "#{origin_source}.yml")
        ]

        local_paths.each do |local_path|
          return SchemaGraphy::Loader.load_yaml_with_tags(local_path) if File.exist?(local_path)
        end

        # Fallback to built-in mapping shipped with gem
        gem_root = File.expand_path('../..', __dir__) # adjust if needed
        built_in_paths = [
          File.join(gem_root, 'lib/releasehx/rhyml/mappings', "#{origin_source}.yaml"),
          File.join(gem_root, 'lib/releasehx/rhyml/mappings', "#{origin_source}.yml")
        ]

        built_in_paths.each do |built_in_path|
          if File.exist?(built_in_path)
            ReleaseHx.logger.debug "Found mapping at: #{built_in_path}"
            return SchemaGraphy::Loader.load_yaml_with_tags(built_in_path)
          end
        end

        # Better error message showing what was tried
        tried_paths = local_paths + built_in_paths
        raise Thor::Error, <<~ERRMSG
          No mapping file found for source '#{origin_source}'.

          Searched in these locations:
          #{tried_paths.map { |p| "  - #{p}" }.join("\n")}

          Solutions:
          1. Create a mapping file in #{local_dir}/#{origin_source}.yaml
          2. Use --mapping to specify a custom mapping file path
          3. Check that config.origin.source is set correctly (currently: '#{origin_source}')
        ERRMSG
      end
    end

    def determine_payload_type identifier
      return :yaml if identifier.end_with?('.yml', '.yaml')
      return :json if options[:api_data]

      :api
    end

    def render_template template_path, context
      engine = Tilt.new(template_path)
      engine.render(Object.new, context)
    end

    def fetch_or_load_issues identifier, source_type
      if source_type == :yaml
        load_yaml_issues(identifier)
      elsif source_type == :json
        load_json_issues(options[:api_data])
      else
        fetch_issues_from_api(identifier)
      end
    end

    def generate_requested_outputs version, issues, source_type
      if options[:yaml]
        output_yaml(version, issues)
      elsif options[:md]
        output_markdown(version, issues, source_type)
      elsif options[:adoc]
        output_asciidoc(version, issues, source_type)
      end

      enrich_docs(source_arg, version)
    end

    def enrich_docs source_path, version
      input_info = determine_input_type(source_path)

      case input_info[:type]
      when :file, :draft
        enrich_from_draft_file(input_info[:path], version)
      when :api
        enrich_direct_from_source(source_path, version)
      else
        ReleaseHx.logger.error('Unable to determine input type for enrichment.')
      end
    end

    def enrich_from_draft_file file_path, version
      unless File.exist?(file_path)
        ReleaseHx.logger.warn("Draft file not found: #{file_path}")
        return
      end

      apply_enrich_modes_to_config

      if options[:html]
        html_out = resolve_enrich_path(:html, version)
        ReleaseHx::EnrichOps.enrich_from_file(
          file_path,
          format: :html,
          config: @settings,
          outpath: html_out,
          force: options[:over])
        ReleaseHx.logger.info("HTML processed: #{html_out}")
      end

      return unless options[:pdf]

      pdf_out = resolve_enrich_path(:pdf, version)
      ReleaseHx::EnrichOps.enrich_from_file(
        file_path,
        format: :pdf,
        config: @settings,
        outpath: pdf_out,
        force: options[:over])
      ReleaseHx.logger.info("PDF processed: #{pdf_out}")
    end

    # Take from API/JSON source to RHYML object, then enrich
    def enrich_direct_from_source source_path, version
      unless options[:fetch]
        ReleaseHx.logger.warn("No draft found for enriching version #{version}. Use --fetch to generate from source.")
        return
      end

      ReleaseHx.logger.info('Creating RHYML object from source for direct enrichment.')
      release = create_rhyml_from_source(source_path, version)

      apply_enrich_modes_to_config

      if options[:html]
        html_out = resolve_enrich_path(:html, version)
        ReleaseHx::EnrichOps.enrich_from_rhyml(
          release: release, format: :html, outpath: html_out, config: @settings,
          force: options[:over])
        ReleaseHx.logger.info("HTML processed: #{html_out}")
      end

      return unless options[:pdf]

      pdf_out = resolve_enrich_path(:pdf, version)
      ReleaseHx::EnrichOps.enrich_from_rhyml(
        release: release, format: :pdf, outpath: pdf_out, config: @settings,
        force: options[:over])
      ReleaseHx.logger.info("PDF processed: #{pdf_out}")
    end

    def create_rhyml_from_source source_path, version
      # First check if source_path is actually a file (overrides config)
      if version_or_file(source_path) == :file && File.exist?(source_path)
        # Load RHYML data directly from YAML file
        ReleaseHx.logger.debug "Loading RHYML from file: #{source_path}" if options[:verbose]
        rhyml_data = SchemaGraphy::Loader.load_yaml_with_tags(source_path)
        release_data = rhyml_data['releases'] ? rhyml_data['releases'].first : rhyml_data

        # Convert hash keys to keyword arguments for Release constructor
        return ReleaseHx::RHYML::Release.new(
          code: release_data['code'] || version,
          date: release_data['date'],
          hash: release_data['hash'],
          memo: release_data['memo'],
          changes: release_data['changes'] || [])
      end

      # Determine source type from configuration
      configured_source_type = @settings.dig('origin', 'source') || 'json'

      # Handle different source types based on configuration
      case configured_source_type
      when 'rhyml'
        # Config says rhyml but source_path is not a file - error
        raise Thor::Error,
              "ERROR: origin.source is 'rhyml' but no YAML file provided. " \
              'Specify a YAML file path as the first argument.'
      when 'json'
        # For json type, only use local files (never API calls)
        if options[:api_data]
          issues = load_json_issues(options[:api_data])
        else
          raise Thor::Error,
                "ERROR: origin.source is 'json' but no --api-data file provided. " \
                'Use --api-data PATH to specify a JSON file.'
        end

        ReleaseHx::DraftOps.from_payload(
          payload: issues,
          config: @settings,
          mapping: load_mapping,
          release_code: version)
      when 'jira', 'github', 'gitlab'
        # For API sources, use cached data if provided, otherwise fetch from API
        issues = if options[:api_data]
                   load_json_issues(options[:api_data])
                 else
                   fetch_issues_from_api(version)
                 end
        ReleaseHx::DraftOps.from_payload(
          payload: issues,
          config: @settings,
          mapping: load_mapping,
          release_code: version)
      else
        raise Thor::Error,
              "ERROR: Unsupported source type '#{configured_source_type}'. " \
              'Must be one of: json, rhyml, jira, github, gitlab'
      end
    end

    def apply_enrich_modes_to_config
      # Apply CLI flags to config for template enrichment
      @settings['modes'] ||= {}

      unless options[:wrap].nil?
        @settings['modes']['wrapped'] = options[:wrap]
        ReleaseHx.logger.info "✓ Changed HTML wrapping to: #{options[:wrap]}" if options[:verbose]
      end

      return if options[:frontmatter].nil?

      @settings['modes']['html_frontmatter'] = options[:frontmatter]
      ReleaseHx.logger.info "✓ Changed frontmatter inclusion to: #{options[:frontmatter]}" if options[:verbose]
    end

    def resolve_enrich_path flag, version
      # Check if user provided a custom path
      user_path = options[flag]
      if user_path && !user_path.empty?
        ReleaseHx.logger.info "✓ Custom output path for #{flag}: #{user_path}" if options[:verbose]
        return user_path
      end

      ext = case flag
            when :pdf  then 'pdf'
            when :html then 'html'
            else raise ArgumentError, "Unknown enrich format: #{flag}"
            end

      template_obj = @settings.dig('paths', 'enrich_filename')
      context = { 'version' => version, 'format_ext' => ext }

      # Use the existing templating system to render the filename
      filename = if template_obj.respond_to?(:render)
                   template_obj.render(context)
                 elsif template_obj.is_a?(String)
                   # It's a plain string, compile and render with Liquid
                   compiled = Liquid::Template.parse(template_obj)
                   compiled.render(context)
                 else
                   template_obj.to_s
                 end

      output_dir = @settings.dig('paths', 'output_dir')
      enrich_dir = @settings.dig('paths', 'enrich_dir')

      File.join(output_dir, enrich_dir, filename.strip)
    end

    # IMPORTANT: This method is currently not used (identified by debride)
    # Similar to find_existing_drafts but with simpler path handling
    # Will be replaced as part of the draft handling refactor
    def find_existing_draft version
      ["#{version}.adoc", "#{version}.md", "#{version}.yml"].find { |f| File.exist?(f) }
    end

    def output_yaml path, _issues
      yaml_content = "---\n#YAML Draft" # placeholder
      safe_write(path, yaml_content)
    end

    def output_markdown path, _issues, _source_type
      markdown_content = "# Markdown Draft\n\n" # placeholder
      safe_write(path, markdown_content)
    end

    def output_asciidoc path, _issues, _source_type
      content = "= AsciiDoc Draft\n\n" # placeholder
      safe_write(path, content)
    end

    def safe_write filename, content
      ReleaseHx.logger.debug("Attempting to write file #{filename}")
      if File.exist?(filename) && !options[:over]
        ReleaseHx.logger.warn("#{filename} already exists. Use --force to overwrite.")
      else
        File.write(filename, content)
        ReleaseHx.logger.info("Draft written: #{filename}")
      end
    end

    def load_yaml_issues path
      ReleaseHx.logger.info("Loading YAML issues from #{path}")
      SchemaGraphy::Loader.load_yaml_with_tags(path)
    end

    def load_json_issues path
      ReleaseHx.logger.info("Loading JSON issues from #{path}")
      payload = JSON.parse(File.read(path))

      # Extract issues array if client config specifies root_issues_path: "issues"
      # This matches what the API client does when fetching live data
      origin_source = @settings.dig('origin', 'source')
      if origin_source && payload.is_a?(Hash) && payload.key?('issues')
        client_path = find_api_client_config(origin_source)
        if client_path
          client_def = SchemaGraphy::Loader.load_yaml_with_tags(client_path)
          if client_def['root_issues_path'] == 'issues'
            ReleaseHx.logger.debug "Extracting 'issues' array from payload"
            return payload['issues']
          end
        end
      end

      payload
    end

    def find_api_client_config origin_source
      local_dir = @settings.dig('paths', 'api_clients_dir') || '_apis'
      local_paths = [
        File.join(local_dir, "#{origin_source}.yaml"),
        File.join(local_dir, "#{origin_source}.yml")
      ]

      local_paths.each do |local_path|
        return local_path if File.exist?(local_path)
      end

      # Check built-in clients
      gem_root = File.expand_path('../..', __dir__)
      builtin_paths = [
        File.join(gem_root, 'lib/releasehx/rest/clients', "#{origin_source}.yaml"),
        File.join(gem_root, 'lib/releasehx/rest/clients', "#{origin_source}.yml")
      ]

      builtin_paths.each do |builtin_path|
        return builtin_path if File.exist?(builtin_path)
      end

      nil
    end

    def fetch_issues_from_api version
      ReleaseHx.logger.info("Fetching issues for version #{version} from API using config")

      client = ReleaseHx::REST::YamlClient.new(@settings, version)
      results = client.fetch_all

      if options[:payload]
        ReleaseHx.logger.info '✓ Will save API payload to file' if options[:verbose]
        save_api_payload(results, options[:payload])
      else
        ReleaseHx.logger.info("Fetched #{results.size} issues from API for version #{version}")
      end

      results
    end

    def save_api_payload results, custom_path = nil
      if custom_path && !custom_path.empty?
        payload_file = custom_path
        payload_dir = File.dirname(payload_file)
        FileUtils.mkdir_p(payload_dir)
      else # Use default path when --payload used without value
        payload_dir = @settings.dig('paths', 'payloads_dir') || 'payloads'
        FileUtils.mkdir_p(payload_dir)
        origin_source_name = @settings.dig('origin', 'source') || 'unknown'
        payload_file = File.join(payload_dir, "#{origin_source_name}.json")
      end

      File.write(payload_file, JSON.pretty_generate(results))
      ReleaseHx.logger.info("API payload saved to #{payload_file}")
    end

    def file_format file_path
      ext = File.extname(file_path).downcase
      case ext
      when '.yml', '.yaml' then :yaml
      when '.md' then :markdown
      when '.adoc' then :asciidoc
      else :unknown
      end
    end

    def merge_cli_flags_into_settings
      @settings['cli_flags'] = {
        'force' => options[:over],
        'fetch' => options[:fetch],
        'verbose' => options[:verbose],
        'debug' => options[:debug],
        'internal' => options[:internal],
        'wrap' => options[:wrap],
        'frontmatter' => options[:frontmatter],
        'empty_notes' => options[:emptynotes]
      }.compact
    end

    def apply_cli_overrides
      return unless options[:output_dir] && !options[:output_dir].empty?

      @settings['paths'] ||= {}
      @settings['paths']['output_dir'] = options[:output_dir]
      ReleaseHx.logger.info "✓ Changed output directory to: #{options[:output_dir]}"
    end
  end
end
