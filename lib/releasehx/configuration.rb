# frozen_string_literal: true

require 'psych'
require_relative '../schemagraphy/loader'

module ReleaseHx
  # Manages the application's configuration by loading and merging settings
  #  from a definition file and a user-provided configuration file.
  class Configuration
    # Public: Global gem attributes copied from the generated README attributes.
    #
    # This constant is used to locate the internal schema/definition file and
    # to determine sane defaults for the user's configuration path.
    # @return [Hash] Global attributes for the gem.
    GEM_GLOBALS = ReleaseHx::ATTRIBUTES[:globals].freeze
    GEM_ROOT_PATH = File.expand_path('../..', __dir__).freeze
    # @return [String] The path to the internal configuration definition file.
    CONFIG_DEF_PATH = File.join(
      GEM_ROOT_PATH,
      GEM_GLOBALS['gem_config_definition_path']).freeze
    # @return [String] The default path to the user's configuration file.
    DEFAULT_CONFIG_PATH = File.join(
      File.expand_path('.'),
      GEM_GLOBALS['app_default_config_path'] || 'releasehx.yml').freeze

    # @param settings [Hash] A hash of configuration settings.
    def initialize settings = {}
      @settings = settings
    end

    # Loads and merges the user configuration with the internal definition/schema
    #  and performs the SGYML precompilation and staged rendering.
    #
    # This method returns a fully-resolved Configuration object suitable for use across the application.
    #
    # @param user_config_path [String] Path to the user's config file (defaults to app default).
    # @param definition_path [String] Path to the internal schema/definition file.
    # @return [Configuration] The final, merged configuration object.
    def self.load user_config_path = DEFAULT_CONFIG_PATH, definition_path = CONFIG_DEF_PATH
      ReleaseHx.logger.debug "Loading configuration from: #{user_config_path}"

      # Use SchemaGraphy to load config definition with resolved attributes
      attrs = ReleaseHx::ATTRIBUTES[:globals]
      definition = SchemaGraphy::Loader.load_yaml_with_attributes(definition_path, attrs)
      SchemaGraphy::SchemaUtils.crawl_meta(definition, 'history.head')

      user_config = File.exist?(user_config_path) ? SchemaGraphy::Loader.load_yaml_with_tags(user_config_path) : {}
      merged_settings = apply_schema(definition['properties'], user_config)
      config = new(merged_settings)

      ReleaseHx::SgymlHelpers.precompile_from_schema!(
        config.settings,
        definition, # should contain $schema or be the schema
        scope: { 'config' => config.settings })
      ReleaseHx::SgymlHelpers.render_stage_fields!(config.settings, :load)

      config
    end

    # Provides convenient dot-style access to top-level configuration sections.
    #
    # Example:
    #   config = ReleaseHx::Configuration.load
    #   source = config.origin['source']
    #
    # This method returns the sub-hash stored under the given key name when present;
    #  otherwise it delegates to the normal method_missing implementation.
    def method_missing(name, *args, &)
      # If settings has a key matching the method name, return that sub-hash
      key_str = name.to_s
      return settings[key_str] if settings.key?(key_str)

      super
    end

    # Indicates whether the configuration has a setting for the given key.
    #
    # @param name [Symbol] The method name being queried.
    # @param include_private [Boolean] Whether to include private methods.
    # @return [Boolean] True if the key exists in settings; otherwise false.
    def respond_to_missing? name, include_private = false
      settings.key?(name.to_s) || super
    end

    # @return [Hash] The underlying hash of configuration settings.
    attr_reader :settings

    # Provides bracket access to configuration settings.
    #
    # Accepts String or Symbol keys and returns the stored value (or nil).
    #
    # @param key [String, Symbol] The key to access.
    # @return [Object] The value associated with the key.
    def [] key
      @settings[key.to_s]
    end

    # @api private
    # Recursively applies schema defaults and normalizes the user's config.
    #
    # Special handling:
    # - A user value of the literal string "$nil" will explicitly remove the
    #   property (treated as nil)
    # - Unknown user-supplied keys are preserved so extensions are not lost
    #
    # @param schema_properties [Hash] The properties from the schema.
    # @param user_hash [Hash] The user's configuration hash.
    # @return [Hash] The merged hash with defaults applied.
    def self.apply_schema schema_properties, user_hash
      final_hash = {}

      (schema_properties || {}).each do |prop_key, prop_def|
        user_val = user_hash.fetch(prop_key, nil)
        # Skip processing this property if user explicitly set it to $nil
        unless user_val.to_s.strip == '$nil'
          final_val = apply_property(prop_def, user_val)
          final_hash[prop_key] = final_val
        end
      end

      # Preserves extra user-supplied keys that aren't in the definition/schema
      user_hash.each do |unk_key, unk_val|
        final_hash[unk_key] = unk_val unless final_hash.key?(unk_key) || unk_val.to_s.strip == '$nil'
      end

      final_hash
    end

    # @api private
    # Applies a single property definition from the schema to a user-supplied value.
    #
    # Handles nested objects and array defaults declared in the schema.
    # User values are preserved unless they are absent (nil) or explicitly set to the literal "$nil" marker.
    #
    # @param prop_def [Hash] The property definition from the schema.
    # @param user_val [Object] The user's value for this property.
    # @return [Object] The final value for the property.
    def self.apply_property prop_def, user_val
      return nil if user_val.to_s.strip == '$nil'

      default_val = prop_def['dflt'] if prop_def.key?('dflt')
      val = user_val.nil? ? default_val : user_val

      # If this prop has nested "properties", treat as a sub-object
      if prop_def['properties']
        val_hash = val.is_a?(Hash) ? val : {}
        # recursively handle sub-properties
        val = apply_schema(prop_def['properties'], val_hash)
      elsif prop_def['type'] == 'ArrayList' && val.nil?
        # It's an array type with a default and we have no user value
        val = default_val || []
      end

      val
    end

    # List of configuration validation rules used by {validate_config}.
    # Each rule is a Hash with :scopes, :message and :check (callable).
    #
    # The :check callable should raise an ArgumentError when validation fails.
    #
    # @return [Array<Hash>] A list of validation rules.
    VALIDATION_RULES = [
      {
        scopes: [:fetch],
        message: "'origin.href' is required for remote sources",
        check: lambda { |config|
          if %w[jira github gitlab].include?(config.origin['source']) && config.origin['href'].to_s.empty?
            raise ArgumentError, "'origin.href' is required for remote source '#{config.origin['source']}'"
          end
        }
      },
      {
        scopes: [:fetch],
        message: "'rhyml' file must exist at origin.href",
        check: lambda { |config|
          if config.origin['source'] == 'rhyml' && !File.exist?(config.origin['href'].to_s)
            raise ArgumentError, "Missing RHYML file at: #{config.origin['href']}"
          end
        }
      }
    ].freeze

    # Validates the configuration against rules that match the provided scopes.
    #
    # @param config [Configuration] The configuration object to validate.
    # @param scopes [Array<Symbol>] The scopes to validate against.
    def self.validate_config config, *scopes
      scopes.flatten!
      rules = VALIDATION_RULES.select { |rule| rule[:scopes].intersect?(scopes) }
      rules.each { |rule| rule[:check].call(config) }
    end

    # Scans built-in and custom mapping files and produces a unique list of known API source names.
    # The result always includes the special entries 'rhyml' and 'git'.
    #
    # @param config [Configuration] The configuration object.
    # @return [Array<String>] A unique list of known API source names.
    def self.known_api_sources config
      builtin_path = File.join(GEM_ROOT_PATH, 'lib/releasehx/rhyml/mappings')
      custom_path = File.expand_path(config.paths['mappings_dir'] || '_mappings')

      mapping_files = Dir["#{builtin_path}/*.{yml,yaml}", "#{custom_path}/*-api.yml"]

      base_names = mapping_files.map do |file|
        base = File.basename(file).sub(/\.ya?ml$/, '')
        base.sub('-api', '')
      end

      base_names = base_names.reject { |name| name == 'verb_past_tenses' }

      (base_names + %w[rhyml git]).uniq
    end
  end
end
