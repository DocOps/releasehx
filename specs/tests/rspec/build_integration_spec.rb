# frozen_string_literal: true

require_relative 'spec_helper'
require 'fileutils'
require 'open3'

RSpec.describe 'ReleaseHx Build Integration' do
  describe 'Prebuild System' do
    it 'executes prebuild task successfully' do
      result = system('rake prebuild')
      expect(result).to be(true), 'rake prebuild failed'
    end

    it 'generates lib/releasehx/generated.rb' do
      system('rake prebuild') unless File.exist?('lib/releasehx/generated.rb')
      expect(File.exist?('lib/releasehx/generated.rb')).to be true
    end

    it 'CLI can load and access generated attributes' do
      system('rake prebuild') unless File.exist?('lib/releasehx/generated.rb')

      # Test that CLI can load without errors
      expect { require 'releasehx/cli' }.not_to raise_error

      # Test that version info is accessible
      expect { ReleaseHx.attrs }.not_to raise_error
      attrs = ReleaseHx.attrs

      # Look for version-related keys
      version_keys = attrs.keys.select { |k| k.include?('version') }
      expect(version_keys).not_to be_empty, "No version-related attributes found. Available: #{attrs.keys}"
    end
  end

  describe 'Configuration Loading' do
    it 'loads demo configurations successfully', skip: ENV['CI'] ? 'Demo repo not available in CI' : false do
      demo_configs = Dir.glob('../*-demo/**/releasehx*.yml') +
                     Dir.glob('examples/**/*.yml')

      expect(demo_configs).not_to be_empty, 'No demo configs found'

      demo_configs.first(3).each do |config_file|
        expect do
          ReleaseHx::Configuration.load(config_file)
        end.not_to raise_error, "Failed to load #{config_file}"
      end
    end

    it 'handles templated configuration fields' do
      # Test with a simple templated config
      config_content = <<~YAML
        origin:
          source: github
          href: "https://api.github.com/repos/test/repo/issues"
        templates:
          output_path: "output/{{ version }}.md"
        version: "1.0.0"
      YAML

      temp_file = Tempfile.new(['test-config', '.yml'])
      temp_file.write(config_content)
      temp_file.close

      begin
        config = ReleaseHx::Configuration.load(temp_file.path)
        expect(config).to be_a(ReleaseHx::Configuration)
        expect(config.origin['source']).to eq('github')
      ensure
        temp_file.unlink
      end
    end
  end

  describe 'Error Handling' do
    it 'provides helpful error when prebuild not run' do
      # Temporarily move generated.rb if it exists
      generated_backup = nil
      if File.exist?('lib/releasehx/generated.rb')
        generated_backup = File.read('lib/releasehx/generated.rb')
        FileUtils.mv('lib/releasehx/generated.rb', 'lib/releasehx/generated.rb.bak')
      end

      begin
        # Should handle missing generated.rb with a helpful error
        cmd = ['ruby', '-Ilib', '-e',
               'begin; require "releasehx"; rescue LoadError => e; puts e.message; exit 0; end; exit 1']
        stdout, _stderr, status = Open3.capture3(*cmd)
        expect(status.success?).to be(true)
        expect(stdout).to match(/prebuild artifacts missing/i)
      ensure
        # Restore generated.rb if we backed it up
        if generated_backup
          FileUtils.mv('lib/releasehx/generated.rb.bak', 'lib/releasehx/generated.rb')
        end
      end
    end
  end
end
