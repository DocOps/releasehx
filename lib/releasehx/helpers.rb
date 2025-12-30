# frozen_string_literal: true

module ReleaseHx
  # Utility methods for file format handling and extension mapping.
  # Provides helpers for converting between file extensions and canonical format names.

  # A map of file extensions to their canonical format names.
  # Used internally by format detection and extension resolution methods.
  #
  # @return [Hash<String, String>] Extension-to-format mapping.
  #
  # TODO: We should externalize this into a YAML file for easier docs integration.
  #       Maybe even something that goes in Sourcerer or somewhere to universalize these.
  FORMAT_MAP = {
    'md' => 'markdown',
    'mkd' => 'markdown',
    'mkdn' => 'markdown',
    'mdown' => 'markdown',
    'markdown' => 'markdown',
    'ad' => 'asciidoc',
    'adoc' => 'asciidoc',
    'asciidoc' => 'asciidoc',
    'yaml' => 'yaml',
    'yml' => 'yaml',
    'json' => 'json',
    'pdf' => 'pdf',
    'html' => 'html'
  }.freeze

  # Resolves the user's preferred file extension for a given format.
  # Consults the configuration's extension preferences and falls back to format detection.
  #
  # @param string [String] The format or extension to look up.
  # @param config [Hash] The configuration hash containing extension preferences.
  # @return [String] The preferred file extension.
  def self.format_extension string, config
    return string unless config.is_a?(Hash) && config.key?('extensions')

    format = file_format_id(string)
    return string.downcase unless format

    config.dig('extensions', format) || string.downcase
  end

  # Converts a file extension or format name to its canonical format identifier.
  # Used to normalize various extension formats (e.g., 'md', 'mkd', 'markdown') to a standard ID.
  #
  # @param key [String] The format or extension to look up.
  # @return [String, nil] The canonical format ID, or nil if not recognized.
  def self.file_format_id key
    return nil if key.nil?

    string = key.to_s.strip
    return nil if string.empty?

    FORMAT_MAP[string.downcase]
  end
end
