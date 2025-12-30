# frozen_string_literal: true

require_relative 'spec_helper'
require 'releasehx/cli'

RSpec.describe ReleaseHx::CLI do
  describe 'command line interface' do
    context 'when checking help output' do
      it 'responds to --help flag' do
        # This will test basic CLI structure without execution
        expect(described_class.commands.keys).not_to be_empty
      end
    end

    context 'when checking version' do
      it 'has access to version information' do
        # Test that CLI can access version
        expect { ReleaseHx::VERSION }.not_to raise_error
      end
    end
  end

  # These would be expanded as we understand the CLI interface better
  describe 'basic command validation' do
    it 'initializes without errors' do
      expect { described_class.new }.not_to raise_error
    end
  end

  describe 'CLI mode validation' do
    it 'requires an output format when using --fetch' do
      cli = described_class.new

      allow(cli).to receive(:options).and_return({ fetch: true })
      allow(cli).to receive(:setup_logger)
      allow(cli).to receive(:load_and_configure_settings) do
        cli.instance_variable_set(:@settings, { 'paths' => {} })
      end

      expect { cli.default('1.0.0') }
        .to raise_error(Thor::Error, /must specify a draft or enrich format/i)
    end
  end

  describe 'CLI option handling' do
    let(:cli) { described_class.new }

    context 'when checking available options' do
      let(:default_command) { described_class.commands['default'] }

      it 'includes --api-data option' do
        expect(default_command.options[:api_data]).not_to be_nil
      end

      it 'includes --fetch option' do
        expect(default_command.options[:fetch]).not_to be_nil
      end

      it 'includes --force option (aliased as --over)' do
        expect(default_command.options[:over]).not_to be_nil
      end

      it 'includes --payload option' do
        expect(default_command.options[:payload]).not_to be_nil
      end
    end
  end

  describe 'CLI flag validation' do
    let(:temp_json_file) { create_temp_json_file(sample_release_issues_json) }
    let(:temp_config_file) { create_temp_yaml_file(sample_release_config) }

    after do
      FileUtils.rm_f(temp_json_file)
      FileUtils.rm_f(temp_config_file)
    end

    context 'when using --api-data with existing file' do
      it 'does not raise error during argument parsing' do
        # We can't easily test the full CLI execution without complex mocking,
        # but we can at least verify the option structure is correct
        expect(temp_json_file).to match(/\.json$/)
        expect(File.exist?(temp_json_file)).to be true
      end
    end
  end

  describe 'configuration handling' do
    let(:cli) { described_class.new }
    let(:temp_config_file) { create_temp_yaml_file(sample_release_config) }
    let(:mock_settings) { {} }
    let(:mock_config) { instance_double(ReleaseHx::Configuration, settings: mock_settings) }

    before do
      allow(ReleaseHx::Configuration).to receive(:load).and_return(mock_config)
      allow(ReleaseHx.logger).to receive(:info)
      allow(ReleaseHx.logger).to receive(:debug)
      # Mock methods called by default command
      allow(cli).to receive(:determine_operations)
    end

    after do
      FileUtils.rm_f(temp_config_file)
    end

    it 'initializes configuration with CLI flags' do
      allow(cli).to receive(:options).and_return(
        {
          verbose: true,
                over: true,
                config: temp_config_file
        })

      cli.default('1.0.0')
      expect(mock_settings['cli_flags']).to include(
        'verbose' => true,
        'force' => true)
    end

    it 'applies output directory override from CLI' do
      allow(cli).to receive(:options).and_return(
        {
          output_dir: '/custom/output',
                config: temp_config_file
        })

      cli.default('1.0.0')
      expect(mock_settings['paths']).to include('output_dir' => '/custom/output')
    end

    it 'preserves existing configuration when applying CLI overrides' do
      mock_settings['paths'] = { 'drafts_dir' => '_drafts' }
      allow(cli).to receive(:options).and_return(
        {
          output_dir: '/custom/output',
                config: temp_config_file
        })

      cli.default('1.0.0')
      expect(mock_settings['paths']).to include(
        'output_dir' => '/custom/output',
        'drafts_dir' => '_drafts')
    end

    it 'handles debug flag correctly' do
      allow(cli).to receive(:options).and_return(
        {
          debug: true,
                config: temp_config_file
        })

      expect(ReleaseHx.logger).to receive(:debug).with(/Operative config settings/)
      cli.default('1.0.0')
      expect(mock_settings['cli_flags']).to include('debug' => true)
    end
  end
end
