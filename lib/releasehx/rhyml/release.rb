# frozen_string_literal: true

module ReleaseHx
  module RHYML
    # Represents a single versioned release containing metadata and associated changes.
    #
    # The Release class serves as a container for release metadata (version code, date, etc.)
    #  and manages a collection of Change objects that comprise the Release content.
    class Release
      attr_reader :code, :date, :hash, :memo, :changes

      # Initializes a new Release object.
      #
      # @param code [String] The version code for the release (e.g., '1.2.0').
      # @param date [Date, String] The release date.
      # @param hash [String] The Git commit hash associated with the release.
      # @param memo [String] A descriptive memo for the release.
      # @param changes [Array<Change, Hash>] An array of Change objects or Hashes
      #   to be converted into Change objects.
      def initialize code:, date: nil, hash: nil, memo: nil, changes: []
        @code    = code
        @date    = date
        @hash    = hash
        @memo    = memo
        @changes = Array(changes).map { |ch| init_change(ch) }.compact

        ReleaseHx.logger.debug 'Release initialized with changes (post-compact):'
        @changes.each_with_index do |ch, i|
          ReleaseHx.logger.debug "  changes[#{i}]: #{ch.class}" unless ch.nil?
        end
        raise 'Unexpected nil in changes' if @changes.any?(&:nil?)
      end

      # Adds a Change object to the Release.
      #
      # @param change [Change] The Change object to add.
      # @return [Array<Change>] The updated array of Changes.
      def add_change change
        attach_release(change)
        @changes << change
      end

      # Returns the number of Changes in the Release.
      #
      # @return [Integer] The count of Changes.
      def change_count
        changes.size
      end

      # Retrieves a unique, sorted list of contributor logins for the Release.
      #
      # @return [Array<String>] An array of unique contributor names.
      def contributors
        changes.map(&:lead).compact.uniq
      end

      # Calculates a hash with the count of each tag used in the Release.
      #
      # @return [Hash{String => Integer}] A hash where keys are tag names and
      #   values are their counts.
      def tag_stats
        changes.compact.flat_map { |c| c.tags || [] }.tally
      end

      # Converts the Release metadata to a hash representation.
      #
      # @note This method excludes the Changes array from the output.
      # @return [Hash] A hash containing the Release's metadata fields.
      def to_h
        {
          'code' => code,
          'version' => code, # alias for backward compatibility
          'date' => date,
          'hash' => hash,
          'memo' => memo,
          'tag_stats' => tag_stats,
          'contributors' => contributors
        }.compact
      end

      private

      # Initializes a Change object from various input types.
      # Handles both existing Change objects and raw Hash data.
      #
      # @param change [Hash, Change] The item to process into a Change object.
      # @return [Change, nil] A valid Change object or nil if input is invalid.
      def init_change change
        return nil unless change

        if change.is_a?(Change)
          change.release = self
          change
        elsif change.is_a?(Hash)
          begin
            obj = Change.new(change, release: self)
            obj.release = self
            obj
          rescue StandardError => e
            ReleaseHx.logger.warn "Skipping malformed change: #{e.message}"
            nil
          end
        else
          ReleaseHx.logger.warn "Unknown change type: #{ch.class}"
          nil
        end
      end

      # Associates a Change object with this Release by setting its release property.
      #
      # @param change [Change] The Change to associate with this release.
      # @return [Change] The associated Change object.
      def attach_release change
        change.release = self
        change
      end
    end

    # Manages a collection of Release objects for historical tracking.
    #
    # @note This class is currently unused but maintained as part of the core
    #   RHYML data model for future functionality like cross-release analytics.
    class History
      attr_reader :releases

      # Initializes a new, empty History object.
      def initialize
        @releases = []
      end

      # Adds a Release to the history.
      #
      # @param release [Release] The Release to add.
      # @return [Release] The Release that was added.
      def add_release release
        raise ArgumentError, 'Release must be a Release object' unless release.is_a? Release

        @releases << release
        ReleaseHx.logger.debug "Added Release: #{release.code} (#{release.date})"
        release
      end
    end
  end
end
