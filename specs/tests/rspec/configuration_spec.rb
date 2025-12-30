# frozen_string_literal: true

require_relative 'spec_helper'
require 'releasehx/configuration'

RSpec.describe ReleaseHx::Configuration do
  let(:sample_config_def) do
    {
      'properties' => {
        'origin' => {
          'properties' => {
            'source' => { 'dflt' => 'github' },
            'href' => { 'dflt' => nil }
          }
        },
        'paths' => {
          'properties' => {
            'output_dir' => { 'dflt' => '_output' },
            'drafts_dir' => { 'dflt' => '_drafts' }
          }
        }
      }
    }
  end

  let(:sample_user_config) do
    {
      'origin' => {
        'source' => 'gitlab',
        'href' => 'https://gitlab.com/api/v4'
      }
    }
  end

  describe '.load' do
    let(:config_def_path) { create_temp_yaml_file(sample_config_def) }
    let(:user_config_path) { create_temp_yaml_file(sample_user_config) }

    after do
      FileUtils.rm_f(config_def_path)
      FileUtils.rm_f(user_config_path)
    end

    it 'merges default and user configuration' do
      config = described_class.load(user_config_path, config_def_path)
      expect(config.settings['origin']['source']).to eq('gitlab')
      expect(config.settings['paths']['output_dir']).to eq('_output')
    end

    it 'allows CLI flags to be merged' do
      config = described_class.load(user_config_path, config_def_path)
      config.settings['cli_flags'] = {
        'force' => true,
        'verbose' => true
      }
      expect(config.settings['cli_flags']['force']).to be true
    end

    it 'preserves user config overrides' do
      config = described_class.load(user_config_path, config_def_path)
      expect(config.settings['origin']['href']).to eq('https://gitlab.com/api/v4')
    end

    it 'handles missing user config gracefully' do
      config = described_class.load('/nonexistent/config.yml', config_def_path)
      expect(config.settings['origin']['source']).to eq('github')
    end
  end

  describe '#[]' do
    it 'allows bracket access to configuration' do
      config = described_class.new({ 'test' => { 'value' => 123 } })
      expect(config['test']['value']).to eq(123)
    end

    it 'returns nil for missing keys' do
      config = described_class.new({})
      expect(config['nonexistent']).to be_nil
    end
  end

  describe 'method_missing' do
    it 'allows dot notation access to configuration' do
      config = described_class.new({ 'test' => { 'value' => 123 } })
      expect(config.test['value']).to eq(123)
    end

    it 'raises NoMethodError for missing methods' do
      config = described_class.new({})
      expect { config.nonexistent_method }.to raise_error(NoMethodError)
    end
  end

  describe 'nested configuration' do
    it 'handles deeply nested settings' do
      config = described_class.new(
        {
          'a' => { 'b' => { 'c' => 'value' } }
        })
      expect(config['a']['b']['c']).to eq('value')
      expect(config.a['b']['c']).to eq('value')
    end
  end
end
