# frozen_string_literal: true

require 'jsonpath'
require 'jmespath'
require 'liquid'
require 'erb'
require 'yaml'
require 'json'
require_relative '../../schemagraphy'
require_relative '../../schemagraphy/safe_expression'
require_relative '../../sourcerer/jekyll'

module ReleaseHx
  module RHYML
    # Transforms raw API payloads into structured RHYML Release objects.
    #
    # Uses RHYML mapping definitions to extract, transform, and normalize
    # data from various issue management systems into a consistent Release structure.
    class Adapter
      SCHEMA_PATH = File.expand_path('../../../specs/data/rhyml-mapping-schema.yaml', __dir__)
      MAPPING_SCHEMA = SchemaGraphy::Loader.load_yaml_with_tags(SCHEMA_PATH)['$schema']
      SKIP_KEYS = %w[$meta $config changes_array_path].freeze

      # Initializes a new adapter instance with mapping configuration and runtime config.
      #
      # @param mapping [Hash] The RHYML mapping definition containing field transformations.
      # @param config [Hash] Application runtime configuration.
      def initialize mapping:, config:
        @mapping = mapping
        @config = config
        @defaults = load_defaults
      end

      # Transforms a raw data payload into a Release object with mapped changes.
      #
      # @param payload [Hash] The raw data payload to transform (ex: GitHub API response).
      # @param release_code [String] The release identifier/version code.
      # @param release_date [String, nil] Optional release date.
      # @param release_hash [String, nil] Optional git commit hash for the release.
      # @param release_memo [String, nil] Optional release memo/description.
      # @param scan [Boolean] Whether to enable detailed debug logging (default: false).
      # @return [Release] A Release object containing the mapped changes.
      def to_release payload, release_code:, release_date: nil, release_hash: nil, release_memo: nil, scan: false
        ReleaseHx.logger.debug "Adapter.to_release called (scan = #{scan})"
        array_path = mapping['changes_array_path']
        raw_items = resolve_path(array_path, payload)

        if raw_items.nil?
          payload_info = payload.is_a?(Hash) ? payload.keys.inspect : payload.class.name
          ReleaseHx.logger.error "Failed to extract items from path '#{array_path}'. Payload: #{payload_info}"
          raw_items = []
        end

        ReleaseHx.logger.debug "Extracted raw_items (#{raw_items.size}) from path '#{array_path}'"
        ReleaseHx.logger.dump "First raw item: #{raw_items.first.inspect}"

        release = Release.new(
          code: release_code,
          date: release_date,
          hash: release_hash,
          memo: release_memo,
          changes: [])

        ReleaseHx.logger.debug "Mapping #{raw_items.size} raw items..."

        changes = raw_items.map { |raw| transform_change(raw, release: release, scan: scan) }.compact

        if changes.empty?
          ReleaseHx.logger.warn(
            'All mapped changes were nil after transformation. ' \
            "No changes attached to release #{release_code}.")
        else
          with_notes = changes.count { |c| c.note.to_s.strip != '' }
          ReleaseHx.logger.info(
            "Transformed #{changes.size} changes for release #{release_code} (#{with_notes} with notes)")
        end

        ReleaseHx.logger.debug "Adding #{changes.size} changes to release" if scan
        ReleaseHx.logger.debug "First change keys: #{changes.first.to_h.keys.inspect}" if scan && changes.any?
        release.instance_variable_set(:@changes, changes)

        release
      end

      private

      attr_reader :mapping, :config, :defaults

      # @api private
      # Loads default configuration values from the RHYML mapping schema.
      # Provides fallback values for path language and template language.
      #
      # @return [Hash] A hash containing default configuration values.
      def load_defaults
        {
          'path_lang' => SchemaGraphy::SchemaUtils.default_for(MAPPING_SCHEMA, '$config.path_lang') || 'jmespath',
          'tplt_lang' => SchemaGraphy::SchemaUtils.default_for(MAPPING_SCHEMA, '$config.tplt_lang') || 'liquid'
        }
      end

      # @api private
      # Transforms a single raw item into a Change object after mapping and post-processing.
      #
      # @param raw [Hash] The raw data item to transform.
      # @param release [Release] The parent release object.
      # @param scan [Boolean] Whether to enable detailed debug logging (default: false).
      # @return [Change, nil] A Change object, or nil if the change should be skipped.
      def transform_change raw, release:, scan: false
        mapped = map_single_change(raw, release: release)
        ReleaseHx.logger.dump "map_single_change returned: #{mapped.class} - #{mapped.inspect}"

        shaped = postprocess(mapped, scan: scan)

        ReleaseHx.logger.dump "Mapped: #{mapped.inspect}"
        ReleaseHx.logger.dump "Postprocessed: #{shaped.inspect}"

        if shaped.nil?
          ReleaseHx.logger.debug "Change dropped after postprocess: #{mapped.inspect}"
          return nil
        end

        Change.new(shaped, release: release)
      rescue StandardError => e
        ReleaseHx.logger.warn "Change transform error: #{e.class}: #{e.message}"
        ReleaseHx.logger.debug e.backtrace.join("\n")
        nil
      end

      # FIXME: This method's complexity is high and handles multiple responsibilities.
      #        Should be refactored into smaller, focused methods for better maintainability.
      #        A comprehensive refactor is planned for post-0.1.0 releases.
      def map_single_change raw, release:
        result = {}
        path_lang = mapping.dig('$config', 'path_lang') || defaults['path_lang']
        context = { 'config' => @config }

        ReleaseHx.logger.dump "map_single_change starting, result class: #{result.class}"

        mapping.each do |key, defn|
          next if SKIP_KEYS.include?(key) || key.start_with?('_') || defn.nil?

          ReleaseHx.logger.debug "Processing mapping field: #{key}"

          # STEP 1: Render Path Expression if templated
          path_expr = render_if_templated(defn['path'], context, key, 'path')

          # STEP 2: Extract value via path (JMESPath or JSONPath)
          extracted_value = extract_value(raw, path_expr, path_lang)

          # STEP 3: Apply transformations
          current_value = if defn['ruby']
                            apply_ruby_transform(extracted_value, defn, key)
                          elsif defn['tplt']
                            apply_template_transform(extracted_value, defn, key)
                          else
                            extracted_value
                          end

          result[key] = apply_pasterization(key, current_value)
        end

        # STEP 4: Generate chid if a template is provided
        generate_chid!(result, release)

        # Attach raw payload for downstream logic (e.g., placeholder note)
        result['raw'] = raw

        ReleaseHx.logger.dump "map_single_change ending, result: #{result.inspect} (class: #{result.class})"
        result
      end

      # @api private
      # Generates a change ID (chid) using the configured template.
      # Updates the result hash in-place with the generated chid.
      #
      # @param result [Hash] The mapped change data hash to update.
      # @param release [Release] The parent release object for context.
      # @return [void]
      def generate_chid! result, release
        chid_template = @config.dig('rhyml', 'chid')
        return unless chid_template

        ctx = {
          'change' => result,
          'release' => {
            'code' => release.code,
            'date' => release.date,
            'hash' => release.hash
          }
        }

        initialize_liquid_filters

        mapped_chid = if chid_template.respond_to?(:templated?) && chid_template.respond_to?(:render)
                        chid_template.render(ctx)
                      else
                        template = Liquid::Template.parse(chid_template.to_s)
                        template.render(
                          ctx,
                          filters: [::ReleaseHx::RHYML::RHYMLFilters,
                                    ::Sourcerer::Jekyll::Liquid::Filters])
                      end

        result['chid'] = mapped_chid.strip unless mapped_chid.to_s.strip.empty?
      end

      # @api private
      # Applies Ruby code transformation to a value using SchemaGraphy's safe transformation.
      #
      # @param value [Object] The value to transform.
      # @param defn [Hash] The field definition containing the Ruby transformation code.
      # @param key [String] The field key being processed (for error reporting).
      # @return [Object] The transformed value, or original value if transformation fails.
      def apply_ruby_transform value, defn, key
        transformer = SchemaGraphy::SafeTransform.new
        transformer.add_context('path', value)
        transformer.add_context('config', @config)
        transformer.transform(defn['ruby'])
      rescue StandardError => e
        ReleaseHx.logger.error "Ruby execution error for '#{key}': #{e.message}"
        ReleaseHx.logger.debug "Context: path=#{value.inspect}, config=#{@config.inspect}"
        value # Return original value on error
      end

      # @api private
      # Applies template transformation to a value using the configured template engine.
      #
      # @param value [Object] The value to transform.
      # @param defn [Hash] The field definition containing the template.
      # @param key [String] The field key being processed (for error reporting).
      # @return [Object] The transformed value.
      def apply_template_transform value, defn, key
        context = { 'path' => value }
        render_if_templated(defn['tplt'], context, key, 'tplt')
      end

      # @api private
      # Applies pasterization (past tense conversion) to field values if configured.
      # Converts verbs to past tense for fields like 'head' and 'summ'.
      #
      # @param key [String] The field key being processed.
      # @param value [String] The value to potentially pasterize.
      # @return [String] The pasterized value or original value if not configured.
      def apply_pasterization key, value
        return value unless (key == 'head' && @config.dig('rhyml', 'pasterize_head')) ||
                            (key == 'summ' && @config.dig('rhyml', 'pasterize_summ'))

        ReleaseHx::RHYML.pasterize(value)
      end

      # @api private
      # Renders a templated field string using the configured template engine.
      #
      # @param template_def [String, Hash] The template definition to render.
      # @param context [Hash] The context variables for template rendering.
      # @param key [String] The field key being processed (for error reporting).
      # @param field_type [String] The type of field being rendered (for error reporting).
      # @return [String] The rendered template result or original value if not templated.
      def render_if_templated template_def, context, key, field_type
        return template_def unless template_def.is_a?(String) || (template_def.is_a?(Hash) && template_def['value'])

        engine = defaults['tplt_lang'] || 'liquid'
        raw_tpl = template_def.is_a?(Hash) && template_def['__tag__'] ? template_def['value'] : template_def

        case engine
        when 'liquid'
          initialize_liquid_filters
          template = ::Liquid::Template.parse(raw_tpl)
          template.render(context)
        when 'erb'
          compiled = ERB.new(raw_tpl)
          compiled.result_with_hash(context)
        else
          raise "Unsupported template engine: #{engine}"
        end
      rescue StandardError => e
        raise "Error rendering '#{field_type}' template for '#{key}': #{e.message}"
      end

      # @api private
      # Extracts a value from data using a path expression and the specified path language.
      #
      # @param data [Hash] The data structure to extract from.
      # @param path [String] The path expression to evaluate.
      # @param lang [String] The path language to use ('jmespath' or 'jsonpath').
      # @return [Object, nil] The extracted value or nil if extraction fails.
      def extract_value data, path, lang
        return nil unless path.is_a?(String) && !path.empty?

        case lang.downcase
        when 'jmespath'
          JMESPath.search(path, data)
        when 'jsonpath'
          JsonPath.new(path).on(data)
        else
          raise "Unsupported path interpreter: #{lang}"
        end
      rescue StandardError => e
        ReleaseHx.logger.error "Path extraction error (#{lang}): '#{path}' – #{e.message}"
        nil
      end

      # @api private
      # Resolves a path expression against data using the configured or overridden path language.
      #
      # @param expr [String] The path expression to resolve.
      # @param data [Hash] The data structure to extract from.
      # @param override_lang [String, nil] Optional language override for path resolution.
      # @return [Object, nil] The resolved value.
      def resolve_path expr, data, override_lang = nil
        engine = (override_lang || mapping.dig('$config', 'path_lang') || defaults['path_lang']).downcase
        extract_value(data, expr, engine)
      end

      # @api private
      # Post-processes mapped change data by extracting notes/heads and applying filtering logic.
      #
      # @param data [Hash] The mapped change data to post-process.
      # @param scan [Boolean] Whether to enable detailed debug logging (default: false).
      # @return [Hash, nil] The post-processed data or nil if the change should be skipped.
      def postprocess data, scan: false
        ReleaseHx.logger.debug "Entering postprocess with scan=#{scan}"
        ReleaseHx.logger.dump "Data before compact: #{data.inspect}"

        data.compact!
        extract_note_and_head!(data)

        # Save original tags before filtering for display
        original_tags = data['tags'].dup if data['tags']
        data['tags'] = process_tags(data['tags'], data['note'])

        # Handle placeholder notes based on raw tags
        handle_placeholder_notes!(data, original_tags)

        ReleaseHx.logger.debug "Evaluating skip logic for: #{data['tick']}" if scan

        skip_change?(data, scan: scan) ? nil : data
      end

      # @api private
      # Extracts note and head content from change data using configured patterns.
      #
      # @param data [Hash] The change data to extract from.
      # @return [void]
      def extract_note_and_head! data
        sources = SchemaGraphy::TagUtils.detag(@config['conversions']) || {}
        templates = SchemaGraphy::TagUtils.detag(@config['rhyml']) || {}

        note_pattern = sources['note_pattern'] || templates['note_pattern']
        head_pattern = sources['head_pattern'] || templates['head_pattern']
        head_source = sources['head_source']
        note_source = sources['note']

        extract_note!(data, note_source, note_pattern)
        extract_head!(data, head_source, head_pattern)
      end

      # @api private
      # Extracts note content from issue body using a configured regex pattern.
      # Also handles ADF (Atlassian Document Format) transformation to Markdown.
      #
      # @param data [Hash] The change data containing the note to extract from.
      # @param note_source [String] The source field specification for note extraction.
      # @param note_pattern [String] The regex pattern for extracting notes.
      # @return [void]
      def extract_note! data, note_source, note_pattern
        # Keep original content if no match or error
        original_content = data['note']
        return unless original_content

        # STEP 1: Transform ADF to Markdown if applicable
        if original_content.is_a?(Hash) && ReleaseHx::Transforms::AdfToMarkdown.adf?(original_content)
          ReleaseHx.logger.debug 'Detected ADF format in note field, converting to Markdown'

          begin
            # Get section heading from config (only used for description-based extraction)
            section_heading = @config.dig('sources', 'note_heading')
            adf_to_convert = original_content

            # Only extract section if we have a heading configured (description-based notes)
            # For custom fields, convert the entire ADF content
            if section_heading && !section_heading.empty?
              ReleaseHx.logger.debug "Extracting '#{section_heading}' section from ADF"
              adf_to_convert = ReleaseHx::Transforms::AdfToMarkdown.extract_section(
                original_content,
                heading: section_heading)
            else
              ReleaseHx.logger.debug 'No note_heading configured, converting entire ADF content'
            end

            # Convert to Markdown
            markdown_note = ReleaseHx::Transforms::AdfToMarkdown.convert(adf_to_convert)

            # Update data with Markdown version
            data['note'] = markdown_note
            data['note_fmt'] = 'md' # Track format for template routing

            ReleaseHx.logger.debug "ADF converted to Markdown (#{markdown_note.length} chars)"
            original_content = markdown_note # Update for subsequent processing
          rescue StandardError => e
            ReleaseHx.logger.warn "ADF conversion error: #{e.message}"
            ReleaseHx.logger.debug e.backtrace.join("\n")
            # Fall back to original content on error
            data['note'] = original_content.to_s
          end
        end

        # STEP 2: Apply regex pattern extraction if configured
        return unless note_source == 'issue_body' && original_content.is_a?(String) && note_pattern

        ReleaseHx.logger.debug "Extracting note using pattern: #{note_pattern}"
        ReleaseHx.logger.debug "Original content: #{original_content[0..100]}..."

        begin
          # Apply sensible default flag 'm' (multiline/dotall in Ruby) when no flags provided
          pattern_info = SchemaGraphy::RegexpUtils.parse_pattern(note_pattern, 'm')
          ReleaseHx.logger.debug "Parsed pattern: #{pattern_info.inspect}"

          extracted_note = SchemaGraphy::RegexpUtils.extract_capture(
            original_content,
            pattern_info,
            'note')

          if extracted_note
            # Pattern matched - use extracted content
            data['note'] = extracted_note.strip
            ReleaseHx.logger.debug "Extracted note (#{extracted_note.length} chars)"
          else
            # Pattern didn't match - clear the note so empty_notes policy applies
            ReleaseHx.logger.warn "Note pattern did not match for issue #{data['tick']} - no Release Note section found"
            data['note'] = nil
          end
        rescue RegexpError => e
          ReleaseHx.logger.warn "Invalid note_pattern '#{note_pattern}': #{e.message}"
          data['note'] = nil # Clear note on pattern error
        end
      end

      # @api private
      # Extracts head content from release note content using a configured regex pattern.
      # Uses dual-strategy logic for pattern matching against blocks and individual lines.
      #
      # @param data [Hash] The change data containing the note to extract head from.
      # @param head_source [String] The source field specification for head extraction.
      # @param head_pattern [String] The regex pattern for extracting heads.
      # @return [void]
      def extract_head! data, head_source, head_pattern
        return unless head_source =~ /release_note_heading/i && data['note'] && head_pattern.is_a?(String)

        ReleaseHx.logger.debug "Extracting head using pattern: #{head_pattern}"
        ReleaseHx.logger.debug "Note content: #{data['note']}"

        begin
          pattern_info = SchemaGraphy::RegexpUtils.parse_pattern(head_pattern, 'm')
          note_content = data['note']

          extracted_head, matched_segment = extract_head_from_block(note_content, pattern_info)
          extracted_head, matched_segment = extract_head_from_lines(note_content, pattern_info) unless extracted_head

          if extracted_head
            data['head'] = extracted_head.strip
            data['note'] = note_content.sub(matched_segment, '').strip if matched_segment
          end
        rescue RegexpError => e
          ReleaseHx.logger.warn "Invalid head_pattern '#{head_pattern}': #{e.message}"
        end
      end

      # @api private
      # Extracts head content from a block of text using regex pattern matching.
      #
      # @param note_content [String] The note content to search within.
      # @param pattern_info [Hash] The parsed regex pattern information.
      # @return [Array<String, String>, nil] Array containing extracted head and matched segment, or nil.
      def extract_head_from_block note_content, pattern_info
        extracted_head = SchemaGraphy::RegexpUtils.extract_capture(note_content, pattern_info, 'head')
        return nil unless extracted_head

        # Find the exact matched segment to remove
        re = Regexp.new(pattern_info[:regexp].source, pattern_info[:regexp].options | Regexp::MULTILINE)
        match_data = note_content.match(re)
        matched_segment = match_data ? match_data[0] : nil

        [extracted_head, matched_segment]
      end

      # @api private
      # Extracts head content from individual lines using regex pattern matching.
      #
      # @param note_content [String] The note content to search within.
      # @param pattern_info [Hash] The parsed regex pattern information.
      # @return [Array<String, String>, nil] Array containing extracted head and matched line, or nil.
      def extract_head_from_lines note_content, pattern_info
        re = pattern_info[:regexp]
        note_content.each_line do |line|
          next unless (m = line.match(re))

          extracted_head = if m.names.include?('head')
                             m[:head]
                           elsif m.captures.any?
                             m.captures.first
                           else
                             m[0]
                           end
          return [extracted_head, line] # Return head and the matched line
        end
        nil # No match found
      end

      # @api private
      # Handles placeholder note generation for changes that need release notes.
      #
      # @param data [Hash] The change data to potentially update with placeholder notes.
      # @param original_tags [Array<String>] The original tag list before processing.
      # @return [void]
      def handle_placeholder_notes! data, original_tags
        raw_tags = extract_raw_tags(data, original_tags)
        tag_config = @config['tags'] || {}
        rn_slugs = get_release_note_needed_slugs(tag_config)
        empty_note_policy = @config.dig('rhyml', 'empty_notes') || 'skip'
        empty_notes_content = @config.dig('rhyml', 'empty_notes_content') || 'RELEASE NOTE NEEDED'

        note_is_empty = data['note'].to_s.strip == '' || data['note'].nil?
        return unless empty_note_policy == 'empty' && raw_tags.intersect?(rn_slugs) && note_is_empty

        data['note'] = empty_notes_content
      end

      # @api private
      # Extracts raw tag data from various sources in the original payload.
      #
      # @param data [Hash] The change data containing raw payload information.
      # @param original_tags [Array<String>] The original tag list as fallback.
      # @return [Array<String>] Array of raw tag strings in lowercase.
      def extract_raw_tags data, original_tags
        raw_tags = nil
        if data['raw'].is_a?(Hash)
          if data['raw'].key?('labels')
            raw_tags = Array(data['raw']['labels']).map { |l| l.is_a?(Hash) ? l['name'] : l.to_s }
          end
          raw_tags ||= Array(data['raw']['tags']).map(&:to_s) if data['raw'].key?('tags')
        end
        raw_tags ||= Array(original_tags)
        raw_tags.map(&:downcase)
      end

      # @api private
      # Gets slug variations for the 'release_note_needed' tag from tag configuration.
      #
      # @param tag_config [Hash] The tag configuration containing slug mappings.
      # @return [Array<String>] Array of slug strings that indicate a release note is needed.
      def get_release_note_needed_slugs tag_config
        rn_tag_key = 'release_note_needed'
        rn_slug = tag_config.dig(rn_tag_key, 'slug')&.downcase || rn_tag_key.downcase
        rn_slugs = [rn_slug, 'needs:note'] # Always include 'needs:note' for safety
        if respond_to?(:tag_slug_map)
          rn_slugs += tag_slug_map.keys.map(&:downcase).select { |slug| tag_slug_map[slug] == rn_tag_key }
        end
        rn_slugs
      end

      # @api private
      # Processes and maps tags from various formats (arrays, checkbox text) into standardized tag names.
      #
      # @param tags [Array, String] The raw tags to process (array of labels or checkbox text).
      # @param _note [String] The note content (unused parameter for potential future use).
      # @return [Array<String>] Array of processed and mapped tag names.
      def process_tags tags, _note
        # Map and filter tags, but keep all mapped tags for inclusion logic.
        # Only drop tags that are marked for display dropping, not inclusion filtering.
        all_tags = []

        if tags.is_a?(Array)
          # Handle label-based tags (GitHub labels, GitLab labels, etc.)
          all_tags = tags.map(&:to_s).map(&:downcase)
        elsif tags.is_a?(String)
          # Handle text-based checkbox tags from raw description/body content
          all_tags = tags.scan(/^- \[x\] (\w[\w-]{1,25})/im).flatten.map(&:downcase)
        end

        # Map tags through slug map and compact to remove unmapped tags
        mapped_tags = all_tags
                      .uniq
                      .map { |slug| tag_slug_map[slug] }
                      .compact

        # Store all mapped tags (including droppable ones) for inclusion logic
        @all_mapped_tags = mapped_tags

        # Return only non-droppable tags for display
        mapped_tags.reject { |tag| @config.dig('tags', tag, 'drop') == true }
      end

      # @api private
      # Determines whether a change should be skipped based on filtering rules.
      # Uses complex conditional logic for tag inclusion/exclusion and note requirements.
      #
      # @param data [Hash] The change data to evaluate.
      # @param scan [Boolean] Whether to enable detailed debug logging (default: false).
      # @return [Boolean] True if the change should be skipped, false otherwise.
      def skip_change? data, scan: false
        all_tags = Array(@all_mapped_tags || data['tags']).map(&:downcase)

        if excluded_by_tag?(all_tags)
          ReleaseHx.logger.debug 'Skipping change due to excluded tag' if scan
          return true
        end

        return false if note_present?(data, scan: scan)
        return false if included_by_tag?(all_tags, scan: scan)

        if missing_required_note?(all_tags)
          ReleaseHx.logger.debug 'Skipping change due to missing required note' if scan
          return true
        end

        if keep_for_empty_policy?
          ReleaseHx.logger.debug 'Keeping change due to empty_notes policy' if scan
          return false
        end

        ReleaseHx.logger.debug 'Skipping change by default (no note or include tag)' if scan
        true
      end

      # @api private
      # Checks if tags contain any that are marked for exclusion.
      #
      # @param tags [Array<String>] The tags to check for exclusion.
      # @return [Boolean] True if any tag is marked for exclusion.
      def excluded_by_tag? tags
        tags.intersect?(Array(@config.dig('tags', '_exclude')))
      end

      # @api private
      # Checks if a note is present and non-empty in the change data.
      #
      # @param data [Hash] The change data to check for note presence.
      # @param scan [Boolean] Whether to enable detailed debug logging (default: false).
      # @return [Boolean] True if a note is present and non-empty.
      def note_present? data, scan: false
        present = data['note'].to_s.strip != ''
        ReleaseHx.logger.debug 'Keeping change due to note present' if present && scan
        present
      end

      # @api private
      # Checks if tags contain any that are marked for inclusion.
      #
      # @param tags [Array<String>] The tags to check for inclusion.
      # @param scan [Boolean] Whether to enable detailed debug logging (default: false).
      # @return [Boolean] True if any tag is marked for inclusion.
      def included_by_tag? tags, scan: false
        include_tags = Array(@config.dig('tags', '_include'))
        overlap = tags & include_tags
        if overlap.any?
          ReleaseHx.logger.debug "Keeping change due to tag in _include: #{overlap.inspect}" if scan
          return true
        end
        false
      end

      # @api private
      # Checks if tags indicate a missing required note when empty notes policy is 'skip'.
      #
      # @param tags [Array<String>] The tags to check for required note indicators.
      # @return [Boolean] True if a required note is missing.
      def missing_required_note? tags
        return false unless @config.dig('rhyml', 'empty_notes') == 'skip'

        rn_slugs = get_release_note_needed_slugs(@config['tags'] || {})
        tags.intersect?(rn_slugs)
      end

      # @api private
      # Checks if the configuration allows keeping changes with empty notes.
      #
      # @return [Boolean] True if empty notes policy is set to 'empty'.
      def keep_for_empty_policy?
        @config.dig('rhyml', 'empty_notes') == 'empty'
      end

      # @api private
      # Creates and caches a mapping of tag slugs to their canonical tag names.
      #
      # @return [Hash] A hash mapping slug strings to canonical tag names.
      def tag_slug_map
        @tag_slug_map ||= begin
          tag_defs = @config['tags'] || {}
          tag_defs.each_with_object({}) do |(key, value), memo|
            next if %w[_include _exclude].include?(key)

            slug = value.is_a?(Hash) ? (value['slug'] || key) : key
            memo[slug] = key
          end
        end
      end

      # @api private
      # Initializes Liquid templating filters and runtime environment.
      # Ensures filters are registered only once to avoid duplicate registrations.
      #
      # @return [void]
      def initialize_liquid_filters
        return if defined?(@__liquid_ready) && @__liquid_ready

        ::Sourcerer::Jekyll.initialize_liquid_runtime
        ::Liquid::Template.register_filter(::ReleaseHx::RHYML::RHYMLFilters)

        @__liquid_ready = true
      end
    end

    # Loads verb past tense mappings from YAML file for pasterization.
    #
    # @return [Hash] A hash mapping present tense verbs to past tense forms.
    def self.verb_past_tenses
      @verb_past_tenses ||= begin
        yaml_path = File.expand_path('mappings/verb_past_tenses.yml', __dir__)
        YAML.load_file(yaml_path)
      end
    end

    # Converts verbs in input text to past tense using the verb mapping dictionary.
    # Preserves original casing (uppercase, capitalized, lowercase) of the words.
    #
    # @param input [String] The text to pasterize.
    # @return [String] The text with verbs converted to past tense, or original if nil/empty.
    def self.pasterize input
      return input if input.nil? || input.empty?

      input.gsub(/\b(\w+)\b/) do |word|
        replacement = verb_past_tenses[word.downcase]
        next word unless replacement

        # Preserve casing
        if word == word.upcase
          replacement.upcase
        elsif word == word.capitalize
          replacement.capitalize
        else
          replacement
        end
      end
    end
  end
end
