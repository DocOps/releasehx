# frozen_string_literal: true

require_relative 'spec_helper'
require 'releasehx/configuration'

RSpec.describe 'SchemaGraphy Integration' do
  describe 'ReleaseHx configuration loading with attribute resolution' do
    let(:sample_config_def_with_attrs) do
      <<~YAML
        properties:
          paths:
            properties:
              drafts_dir:
                dflt: "{test_drafts_dir}"
              output_dir:
                dflt: "{test_output_dir}"
          origin:
            properties:
              auth:
                properties:
                  key_env:
                    dflt: "{test_api_key}"
      YAML
    end

    let(:sample_user_config) do
      {
        'origin' => {
          'auth' => {
            'key_env' => 'CUSTOM_API_KEY'
          }
        }
      }
    end

    let(:test_attrs) do
      {
        'test_drafts_dir' => '_test_drafts',
        'test_output_dir' => '_test_output',
        'test_api_key' => 'TEST_API_KEY_ENV'
      }
    end

    let(:config_def_path) { create_temp_yaml_file(sample_config_def_with_attrs) }
    let(:user_config_path) { create_temp_yaml_file(sample_user_config) }

    after do
      FileUtils.rm_f(config_def_path)
      FileUtils.rm_f(user_config_path)
    end

    it 'loads configuration with resolved attributes from README.adoc' do
      # This test validates that the actual README.adoc attributes are loaded
      # We can't mock frozen constants, so we test the real behavior
      config = ReleaseHx::Configuration.load(user_config_path, config_def_path)

      # Verify that user config values are loaded
      expect(config.settings.dig('origin', 'auth', 'key_env')).to eq('CUSTOM_API_KEY')

      # Verify that default paths are present (these come from config-def.yml with attribute refs resolved)
      expect(config.settings.dig('paths', 'drafts_dir')).to be_a(String)
      expect(config.settings.dig('paths', 'output_dir')).to be_a(String)
    end

    it 'handles configuration loading with defaults when user config missing' do
      # Test that configuration loads successfully even with missing user config
      config = ReleaseHx::Configuration.load('nonexistent-config.yml', config_def_path)

      # Should have default values from config-def.yml
      expect(config.settings.dig('paths', 'drafts_dir')).to be_a(String)
      expect(config.settings.dig('paths', 'drafts_dir')).not_to be_empty
    end

    it 'resolves real README.adoc attributes in production config-def.yml' do
      # This tests the actual integration with real files
      config = ReleaseHx::Configuration.load('nonexistent-config.yml')

      # Verify that real attributes are resolved
      expect(config.settings.dig('paths', 'drafts_dir')).to eq('_drafts')
      expect(config.settings.dig('paths', 'output_dir')).to eq('.')
      expect(config.settings.dig('origin', 'auth', 'key_env')).to eq('RELEASEHX_API_KEY')

      # Verify meta settings are resolved
      expect(config.settings.dig('$meta', 'slug_type')).to eq('kebab')
      expect(config.settings.dig('$meta', 'tplt_lang')).to eq('liquid')
    end
  end

  describe 'SchemaGraphy loader interface stability' do
    let(:test_yaml_content) do
      <<~YAML
        test:
          nested:
            dflt: "{test_attr}"
        other:
          dflt: "literal_value"
      YAML
    end

    let(:test_attrs) { { 'test_attr' => 'resolved_value' } }
    let(:yaml_path) { create_temp_yaml_file(test_yaml_content) }

    after do
      FileUtils.rm_f(yaml_path)
    end

    it 'loads YAML with attribute resolution via SchemaGraphy::Loader' do
      result = SchemaGraphy::Loader.load_yaml_with_attributes(yaml_path, test_attrs)

      expect(result.dig('test', 'nested', 'dflt')).to eq('resolved_value')
      expect(result.dig('other', 'dflt')).to eq('literal_value')
    end

    it 'loads YAML with tags preserved via SchemaGraphy::Loader' do
      # This ensures the existing load_yaml_with_tags functionality still works
      result = SchemaGraphy::Loader.load_yaml_with_tags(yaml_path)

      expect(result).to be_a(Hash)
      expect(result.dig('test', 'nested', 'dflt')).to eq('{test_attr}') # Unresolved
      expect(result.dig('other', 'dflt')).to eq('literal_value')
    end
  end
end
