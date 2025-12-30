# frozen_string_literal: true

module ReleaseHx
  # The DraftOps module provides methods for creating Release objects and
  # generating draft files from source data like API payloads.
  module DraftOps
    # Converts a raw JSON payload from an issue management system into a
    # ReleaseHx::RHYML::Release object.
    #
    # @param payload [Hash, Array] The raw payload from the API.
    # @param config [ReleaseHx::Configuration] The application configuration.
    # @param mapping [Hash] The mapping definition for converting payload fields.
    # @param release_code [String] The version code for the release.
    # @param release_date [Date, String, nil] The date for the release.
    # @param scan [Boolean] Indicates if this is a scan-only operation.
    # @return [ReleaseHx::RHYML::Release] The generated Release object.
    def self.from_payload payload:, config:, mapping:, release_code:, release_date: nil, scan: false
      adapter = ReleaseHx::RHYML::Adapter.new(mapping: mapping, config: config)

      adapter.to_release(
        payload,
        release_code: release_code,
        release_date: release_date || Date.today,
        scan: scan)
    end

    # Shared method for preparing RHYML object template context
    def self.prepare_template_context release:, config:
      raise ArgumentError, 'release is nil' if release.nil?

      # Establish available datasets
      all_changes = release.changes.select { |ch| ch.respond_to?(:to_h) }
      changes_mapped = all_changes.map(&:to_h)

      sorted = build_sorted_changes(changes_mapped, config)

      context_scope = {
        'release' => release.to_h,
        'changes' => changes_mapped,
        'sorted'  => sorted,
        'config'  => config
      }

      SchemaGraphy::Templating.render_all_templated_fields!(config, context_scope)

      {
        variables: {
          'release' => release.to_h,
          'changes' => changes_mapped,
          'config'  => config,
          'sorted'  => sorted
        },
        context_scope: context_scope
      }
    end

    # Generates a string of content for a draft file (e.g., Markdown, YAML)
    # from a Release object using the configured Liquid templates.
    #
    # @param release [ReleaseHx::RHYML::Release] The release object.
    # @param config [ReleaseHx::Configuration] The application configuration.
    # @param format [Symbol] The output format (:yaml, :md, :adoc, :html).
    # @return [String] The rendered content.
    def self.process_template_content release:, config:, format:
      context = prepare_template_context(release: release, config: config)

      tplt = case format.to_sym
             when :yaml, :yml then 'rhyml.yaml.liquid'
             when :md         then 'release.md.liquid'
             when :adoc       then 'release.adoc.liquid'
             when :html       then 'release.html.liquid'
             else raise ArgumentError, "Unsupported format: #{format}"
             end

      tplt_path = WriteOps.resolve_template_path(tplt, config)
      ReleaseHx.logger.debug "Using template: #{tplt_path}"

      WriteOps.process_template(tplt_path, { 'vars' => context[:variables] }, config)
    end

    # Builds sorted changes structure (moved from EnrichOps)
    def self.build_sorted_changes changes_mapped, config
      sorted = {
        'by' => {
          'tag'  => {},
          'type' => {},
          'part' => {}
        }
      }

      changes_mapped.each do |ch|
        Array(ch['tags']).each do |tag|
          sorted['by']['tag'][tag] ||= []
          sorted['by']['tag'][tag] << ch
        end

        type = ch['type']
        if type
          sorted['by']['type'][type] ||= []
          sorted['by']['type'][type] << ch
        end

        # treat 'parts' differently from type or tags as it is an Array in all cases
        parts = ch['parts']
        next unless parts

        Array(parts).each do |part|
          sorted['by']['part'][part] ||= []
          sorted['by']['part'][part] << ch
        end
      end

      # Ensures all config-defined parts/types/tags are initialized
      Array(config['types']&.keys).each do |type|
        sorted['by']['type'][type] ||= []
      end

      Array(config['parts']&.keys).each do |part|
        sorted['by']['part'][part] ||= []
      end

      Array(config['tags']&.keys).each do |tag|
        next if %w[_include _exclude].include?(tag)

        sorted['by']['tag'][tag] ||= []
      end

      sorted
    end

    # rubocop:disable Lint/UnusedMethodArgument
    def self.append_changes yaml_file_path:, version_code:, config:, mapping:, source_type:, payload: nil, force: false
      # NOTE: force parameter is currently unused but kept for API consistency
      # Load existing YAML Release
      existing_release = ReleaseHx::RHYML::ReleaseLoader.load(yaml_file_path)
      existing_tick_ids = existing_release.changes.map(&:tick).compact

      ReleaseHx.logger.debug "Found #{existing_tick_ids.size} existing changes with tick IDs: #{existing_tick_ids}"

      # Use provided payload or default to API fetch
      payload ||= fetch_payload_for_version(version_code, source_type, config)

      new_release = from_payload(
        payload: payload,
        config: config,
        mapping: mapping,
        release_code: version_code,
        release_date: existing_release.date)

      # Find new changes that weren't in the existing YAML
      new_changes = new_release.changes.select do |change|
        change.tick && !existing_tick_ids.include?(change.tick)
      end

      return 0 if new_changes.empty?

      ReleaseHx.logger.info "Found #{new_changes.size} new changes to append"

      # Generate append content and write it
      WriteOps.append_changes_to_yaml(yaml_file_path, new_changes, config)

      new_changes.size
    end
    # rubocop:enable Lint/UnusedMethodArgument

    # Legacy method kept for backward compatibility
    def self.draft_output release:, config:, format:, outpath:
      content = process_template_content(release: release, config: config, format: format)
      WriteOps.safe_write(outpath, content) if outpath
      content
    end
  end
end
