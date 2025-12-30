# frozen_string_literal: true

module ReleaseHx
  module RHYML
    # Represents a single Change within a Release, such as a bug fix, feature, or enhancement.
    #
    # The Change class encapsulates all metadata associated with an individual modification,
    #  including its classification (type), descriptive content (summary, notes),
    #  organizational data (tags, parts), and contributor information.
    # Changes are always associated with a parent Release object.
    class Change
      attr_accessor :release, :version
      attr_reader :vrsn, :chid, :tick, :hash, :type, :parts, :summ, :head, :note, :tags, :lead, :auths, :links

      # Initializes a new Change object from attribute hash and parent Release.
      #
      # Processes the provided attributes to populate Change properties, handling
      #  multiple possible field names (e.g., 'summ', 'summary', 'title') and
      #  normalizing complex attributes like authors and links.
      #
      # @param attrs [Hash] A hash of attributes for the Change.
      # @param release [Release] The required parent Release object.
      # @raise [ArgumentError] If attrs is not a Hash or if both 'part' and 'parts' are provided.
      def initialize attrs = {}, release:
        raise ArgumentError, 'attrs must be a Hash' unless attrs.is_a? Hash

        @release = release
        @vrsn    = @release.code
        @chid    = attrs['chid']
        @tick    = attrs_value(attrs, %w[tick ticketid])
        @hash    = attrs['hash']
        @type    = attrs['type']
        @summ    = attrs_value(attrs, %w[summ summary title])
        @head    = attrs['head']
        @note    = attrs['note']
        @tags    = attrs['tags'] || []
        @lead    = attrs_value(attrs, %w[lead contributor auth])
        @auths   = normalize_auths(attrs['auths'])
        @links   = normalize_links(attrs['links'])

        # Handle 'part' vs 'parts'; mutually exclusive attributes
        part  = attrs['part']
        parts = attrs['parts']
        raise ArgumentError, "Change cannot have both 'part' and 'parts'" if part && parts

        @parts = if parts
                   Array(parts).map(&:to_s)
                 elsif part
                   [part.to_s]
                 else
                   []
                 end

        ReleaseHx.logger.debug "Initialized Change: #{@tick} – #{@summ}"
      end

      # Produces a comprehensive hash representation of the Change.
      #
      # Includes all public attributes plus computed boolean properties
      # for common Change classifications (highlight, breaking, etc.).
      #
      # @return [Hash] A hash containing all public attributes of the Change.
      def to_h
        {
          'vrsn' => vrsn,
          'chid' => chid,
          'tick' => tick,
          'hash' => hash,
          'type' => type,
          'parts' => parts,
          'summ' => summ,
          'head' => head,
          'note' => note,
          'tags' => tags,
          'lead' => lead,
          'auths' => auths,
          'links' => links,
          'deprecation' => deprecation?,
          'removal' => removal?,
          'highlight' => highlight?,
          'breaking' => breaking?,
          'experimental' => experimental?
        }
      end

      # @return [Boolean] True if the Change is tagged as a highlight.
      def highlight? = tags.include?('highlight')
      # @return [Boolean] True if the Change is a breaking change.
      def breaking?     = tags.include?('breaking')
      # @return [Boolean] True if the Change is experimental.
      def experimental? = tags.include?('experimental')
      # @return [Boolean] True if the Change includes a deprecation.
      def deprecation?  = tags.include?('deprecation')
      # @return [Boolean] True if the Change includes a removal.
      def removal?      = tags.include?('removal')

      # Checks if a given tag is associated with the Change.
      #
      # Performs flexible tag matching, checking for the tag as provided,
      #  as a string, and as a symbol to handle different input types.
      #
      # @param tag_name [String, Symbol] The name of the tag to check.
      # @return [Boolean] True if the tag exists in any form.
      def tag? tag_name
        tags.include?(tag_name) || tags.include?(tag_name.to_s) || tags.include?(tag_name.to_sym)
      end

      private

      # Retrieves the first available attribute value from a prioritized list of keys.
      #
      # Used for handling multiple possible field names in source data
      # (example: 'tick' or 'ticketid', 'summ' or 'summary' or 'title').
      #
      # @param attrs [Hash] The attributes hash to search.
      # @param keys [Array<String>] Ordered list of keys to try.
      # @return [Object, nil] The first found value or nil if none exist.
      def attrs_value attrs, keys
        keys.find { |key| return attrs[key] if attrs.key?(key) }
        nil
      end

      # Normalizes the 'auths' attribute to ensure consistent structure.
      #
      # Converts various input formats (strings, hashes, arrays) into a
      # standardized array of hashes with 'user' and optional 'memo' keys.
      #
      # @param val [String, Hash, Array, nil] The authors data to normalize.
      # @return [Array<Hash>] Normalized array of author hashes.
      def normalize_auths val
        return [] if val.nil?

        Array(val).map do |a|
          if a.is_a?(String)
            { 'user' => a }
          elsif a.is_a?(Hash)
            {
              'user' => a['user'] || a[:user],
              'memo' => a['memo'] || a[:memo]
            }.compact
          else
            { 'user' => a.to_s }
          end
        end
      end

      # Normalizes the 'links' attribute to ensure consistent structure.
      #
      # Ensures all links have standardized 'text', 'xref', and 'href' keys,
      #  converting symbol keys to string keys and filtering out nil values.
      #
      # @param val [Array<Hash>, nil] The links data to normalize.
      # @return [Array<Hash>] Normalized array of link hashes.
      def normalize_links val
        return [] if val.nil?

        val.map do |l|
          {
            'text' => l['text'] || l[:text],
            'xref' => l['xref'] || l[:xref],
            'href' => l['href'] || l[:href]
          }.compact
        end
      end
    end
  end
end
