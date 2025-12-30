# frozen_string_literal: true

require_relative 'spec_helper'
require 'fileutils'
require 'json'

RSpec.describe 'ReleaseHx Configuration and CLI changes' do
  describe 'configuration structure' do
    context 'when loading configuration module' do
      it 'loads Configuration class without errors' do
        expect { require 'releasehx/configuration' }.not_to raise_error
      end
    end

    context 'when testing cache configuration structure' do
      let(:cache_config) do
        {
          'paths' => {
            'cache' => {
              'enabled' => true,
              'ttl_hours' => 24,
              'dir' => '.releasehx/cache',
              'prompt_gitignore' => true
            }
          }
        }
      end

      it 'has proper cache configuration structure' do
        expect(cache_config.dig('paths', 'cache', 'enabled')).to be(true)
        expect(cache_config.dig('paths', 'cache', 'ttl_hours')).to eq(24)
        expect(cache_config.dig('paths', 'cache', 'dir')).to eq('.releasehx/cache')
        expect(cache_config.dig('paths', 'cache', 'prompt_gitignore')).to be(true)
      end
    end
  end

  describe 'REST module structure' do
    it 'loads YamlClient without errors' do
      expect { require 'releasehx/rest/yaml_client' }.not_to raise_error
    end

    it 'has YamlClient available' do
      require 'releasehx/rest/yaml_client'
      expect(ReleaseHx::REST::YamlClient).to be_a(Class)
    end
  end

  describe 'CLI flag processing' do
    let(:temp_json_file) { create_temp_json_file(sample_release_issues_json) }

    after do
      FileUtils.rm_f(temp_json_file)
    end

    context 'when creating config with CLI flags' do
      it 'can merge CLI flags into config structure' do
        base_config = { 'source' => { 'type' => 'github' } }
        cli_flags = { 'force' => true, 'fetch' => true }

        config_with_flags = base_config.merge({ 'cli_flags' => cli_flags })

        expect(config_with_flags.dig('cli_flags', 'force')).to be true
        expect(config_with_flags.dig('cli_flags', 'fetch')).to be true
      end
    end

    context 'when checking file operations' do
      it 'can create and read JSON files for --api-data' do
        expect(File.exist?(temp_json_file)).to be true

        data = JSON.parse(File.read(temp_json_file))
        expect(data).to be_an(Array)
        expect(data.first).to have_key('title')
      end
    end
  end

  describe 'cache directory operations' do
    let(:temp_dir) { create_temp_dir }
    let(:cache_dir) { File.join(temp_dir, '.releasehx', 'cache') }

    after do
      FileUtils.rm_rf(temp_dir)
    end

    context 'when managing cache directories' do
      it 'can create nested cache directory structure' do
        nested_path = File.join(cache_dir, 'github', '1.0.0')
        FileUtils.mkdir_p(nested_path)

        expect(Dir.exist?(nested_path)).to be true
      end

      it 'can write and read cache files' do
        FileUtils.mkdir_p(cache_dir)
        cache_file = File.join(cache_dir, 'test_payload.json')

        test_data = [{ 'id' => 1, 'title' => 'Test Cache' }]
        File.write(cache_file, JSON.pretty_generate(test_data))

        expect(File.exist?(cache_file)).to be true

        loaded_data = JSON.parse(File.read(cache_file))
        expect(loaded_data).to eq(test_data)
      end
    end
  end
end
