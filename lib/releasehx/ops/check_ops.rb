# frozen_string_literal: true

module ReleaseHx
  # Provides validation and reporting methods for Release content quality checks.
  #
  # The CheckOps module contains utilities for verifying Release completeness,
  #  particularly focused on ensuring required release notes are present for
  #  issues that demand them based on configured tag requirements.
  module CheckOps
    # Extracts a value from structured data using the specified path and query language.
    #
    # Supports multiple path query languages including JMESPath for complex JSON
    # navigation and basic hash key lookup for simple access patterns.
    #
    # @param data [Hash, Array] The structured data to query.
    # @param path [String] The path expression for locating the target value.
    # @param lang [String] The query language to use ('jmespath', 'jsonpath', or default hash lookup).
    # @return [Object, nil] The extracted value or nil if path is invalid or value not found.
    def self.extract_value data, path, lang
      return nil unless path.is_a?(String) && !path.empty?

      case lang.downcase
      when 'jmespath'
        JMESPath.search(path, data)
      when 'jsonpath'
        JsonPath.new(path).on(data)
      else
        data[path]
      end
    end

    # Prints a comprehensive summary report of release note completeness.
    #
    # Displays statistics about the Release including issue counts, note coverage,
    # and detailed lists of any issues missing required release notes.
    #
    # @param release [Release] The Release object to report on.
    # @param raw_issues_count [Integer] Total number of issues fetched from the API.
    # @param payload [Hash, Array] The original API payload data.
    # @param config [Hash] The configuration hash containing tag settings.
    # @param mapping [Hash] The field mapping configuration for data extraction.
    # @return [void]
    def self.print_check_summary release, raw_issues_count, payload, config, mapping
      missing_issues = find_missing_note_issues(release, payload, config, mapping)

      puts
      puts 'Release Note Check Report'
      puts
      puts "• Release Code:       #{release.code}"
      puts "• Issues Fetched:     #{raw_issues_count}"
      puts "• Viable Issues:      #{release.changes.size}"
      puts "• Notes Present:      #{release.changes.count { |c| c.note.to_s.strip != '' }}"
      puts "• Missing Notes:      #{missing_issues.size}"

      if missing_issues.any?
        print_issue_list('Missing required release notes:', missing_issues, config, mapping)
      else
        puts
        puts 'No missing release notes!'
      end
      puts
    end

    # Identifies issues that require release notes but are missing them.
    #
    # Searches the original payload for issues tagged with the release note requirement,
    # then cross-references with Changes that already have notes to find gaps.
    #
    # @param release [Release] The Release object containing processed Changes.
    # @param payload [Hash, Array] The original API payload data.
    # @param config [Hash] The configuration hash containing tag settings.
    # @param mapping [Hash] The field mapping configuration for data extraction.
    # @return [Array<Hash>] Array of issue objects missing required release notes.
    def self.find_missing_note_issues release, payload, config, mapping
      # Extract release note requirement configuration
      tag_config = config['tags'] || {}
      rn_tag_key = 'release_note_needed'
      rn_slug = tag_config.dig(rn_tag_key, 'slug')&.downcase || rn_tag_key.downcase

      # Configure data extraction paths
      tick_path = mapping.dig('tick', 'path') || 'number'
      tags_path = mapping.dig('tags', 'path') || 'labels[].name'
      path_lang = mapping.dig('$config', 'path_lang') || 'jmespath'

      # Find issues tagged as requiring release notes
      payload_items = payload.is_a?(Array) ? payload : payload['issues'] || payload.values
      rn_issues = payload_items.select do |item|
        tags = extract_value(item, tags_path, path_lang)
        tags = tags.is_a?(Array) ? tags.map(&:downcase) : Array(tags).map(&:downcase)
        tags.include?(rn_slug)
      end

      # Get ticket IDs that already have notes
      noted_ticks = release.changes.reject { |c| c.note.to_s.strip == '' }.map(&:tick)

      # Return issues that need notes but don't have them
      rn_issues.reject do |item|
        tick = extract_value(item, tick_path, path_lang)
        noted_ticks.include?(tick)
      end
    end

    # Prints a formatted list of issues with extracted metadata.
    #
    # Displays issues in a consistent format with ticket IDs, summaries, and
    #  assignee information, using API-specific formatting conventions.
    #
    # @param title [String] The header title for the issue list.
    # @param issues [Array<Hash>] Array of issue objects to display.
    # @param config [Hash] The configuration hash for API type detection.
    # @param mapping [Hash] The field mapping configuration for data extraction.
    # @return [void]
    def self.print_issue_list title, issues, config, mapping
      puts
      puts title

      # Configure extraction paths for issue metadata
      tick_path = mapping.dig('tick', 'path') || 'number'
      summ_path = mapping.dig('summ', 'path') || 'title'
      lead_path = mapping.dig('lead', 'path') || 'assignee.login'
      path_lang = mapping.dig('$config', 'path_lang') || 'jmespath'
      api_type = config.dig('source', 'type')&.downcase || 'unknown'

      issues.each do |issue|
        tick = extract_value(issue, tick_path, path_lang)
        summ = extract_value(issue, summ_path, path_lang)
        lead = extract_value(issue, lead_path, path_lang)

        # Format ticket display based on API type conventions
        tick_display = api_type == 'jira' ? tick.to_s : "##{tick}"
        lead_display = lead ? " (#{lead})" : ''
        puts " - #{tick_display}: #{summ}#{lead_display}"
      end
    end
  end
end
